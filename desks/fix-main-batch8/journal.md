# fix-main-batch8 — Journal

## 2026-10-19 — Desk opened
- **Purpose:** Batch 8 — the remaining publish-readiness fixes from the arbiter + proctor audits (H1 character/inspect pane refresh, N2 instant-fade handling, N4 options-loader not-applicable rule, the mock-fidelity contract, doc corrections, CHANGELOG/README). No commit, no staging. Every fix revert-to-fail proven in-harness.
- **Scope:** `main.lua`, `options.lua`, `Libs/LibForeverInspector/LibForeverInspector.lua` (comment only), `Tests/harness/*.lua` (pins + mock corrections), `CHANGELOG.md`, `README.md`, `desks/fix-main-batch8/`. NOT `gearscore.lua`, NOT `Locale/`, NOT `*.toc`/versions, NOT `bench/`, NOT other desks.
- **Constraints:** Classic Era inspect range gate FROZEN; raw GearScore formula UNTOUCHED; Retail bracket HOLD at the shared 1000; **no `CanInspect(unit, true)` anywhere**; guild/level line-index ownership proof untouched; `CharacterModelFrame` never indexed unguarded; Locale files not touched; no invented Russian strings; no `*.toc`/version changes; no bench/ or other-desk writes.
- **Baselines (re-run before the first edit):** MAIN `bash Tests/harness/run_all.sh` = **64/64** (lua5.1); Extras `bash TacoTip_Extras/Tests/harness/run_all.sh` = **42/42** (14 per interpreter × 3); `luacheck .` from the repo root = 0/0 in **85** files; `cd TacoTip_Extras && luacheck .` = 0/0 in 26 files.
- **Bench-read:** `bench/audits/2026-10-19-main-addon-arbiter-audit.md`, `bench/audits/2026-10-19-test-sufficiency-audit.md`, `bench/audits/2026-10-19-maintainability-audit.md`; desks `publish-hunter`, `fix-main-batch6`, `fix-main-batch7`. (`desks/main-arbiter` and `desks/proctor-audit` do not exist — their content is the bench audits.)

## 2026-10-19 — Mirror evidence (all five branches)
Source: `/home/sam/wow-ui-source` (read-only), branches `origin/classic_era`, `origin/classic_anniversary`, `origin/classic_titan`, `origin/forever`, `origin/live`.

### H1 — the panes that actually fire OnShow
- `PaperDollFrame` / `InspectPaperDollFrame`: **no `hidden` attribute on any branch** (`<Frame name="PaperDollFrame" setAllPoints="true" enableMouse="true" parent="CharacterFrame" ...>`; `<Frame name="InspectPaperDollFrame" setAllPoints="true" useParentLevel="true" parent="InspectFrame" id="1">`). Shown from creation → OnShow fired before the addon loaded → the hooks on them were dead.
- `CharacterFrame` / `InspectFrame`: **`hidden="true"` on all five** (`<Frame name="CharacterFrame" toplevel="true" movable="true" parent="UIParent" hidden="true" ...>`; `<Frame name="InspectFrame" toplevel="true" movable="true" enableMouse="true" hidden="true" parent="UIParent" ...>`) → their OnShow fires once per pane open.
- `InspectFrame.unit` is set BEFORE the frame is shown: `InspectFrame_Show` sets `InspectFrame.unit = unit` (classic_era `Blizzard_InspectUI/Vanilla/Blizzard_InspectUI.lua:7`, `.../TBC/Blizzard_InspectUI.lua:13`, live `.../Mainline/Blizzard_InspectUI.lua:13`) and `ShowUIPanel(InspectFrame)` happens later on `INSPECT_READY` (`.../Mainline/Blizzard_InspectUI.lua:41`).

### N4 — which LoadAddOn targets exist where (`git ls-tree -d origin/<branch>:Interface/AddOns`)
| target | classic_era | classic_anniversary | classic_titan | forever | live |
|---|---|---|---|---|---|
| `Blizzard_Settings` | ABSENT | ABSENT | ABSENT | PRESENT | PRESENT |
| `Blizzard_Settings_Shared` | PRESENT | PRESENT | PRESENT | PRESENT | PRESENT |
| `Blizzard_SettingsDefinitions` | ABSENT | ABSENT | ABSENT | ABSENT | ABSENT |
| `Blizzard_SettingsDefinitions_Shared` | PRESENT | PRESENT | PRESENT | PRESENT | PRESENT |
| `Blizzard_OptionsUI` | ABSENT | ABSENT | ABSENT | ABSENT | ABSENT |
| `Blizzard_InterfaceOptions` | ABSENT | ABSENT | ABSENT | ABSENT | ABSENT |

### Mock fidelity
- `UnitClass`: **3** on the modern pair (`origin/live` + `origin/forever` — `Blizzard_SharedXML/UnitUtil.lua:81` `local classID = select(3, UnitClass("player"))`; `Blizzard_ClassMenu/Blizzard_ClassMenu.lua:7` `local name, tag, classID = UnitClass("player")`); **2** on the Classic family (`origin/classic_era` — `Blizzard_InspectUI/Vanilla/InspectPaperDollFrame.lua:10` `local classDisplayName, class = UnitClass(InspectFrame.unit);`).
- `GetSpecializationInfoByID`: **7** (`origin/live` — `Blizzard_Communities/ClubFinder.lua:599` `local id, name, description, texture, role, class, classDisplayName = GetSpecializationInfoByID(specId);`).
- `FauxScrollFrame_Update`: **1** — the function body ends at `SecureScrollTemplates.lua:224` with `return showScrollBar;` on **all five** branches (the function starts at `:158`).

## 2026-10-19 — THREE AUDIT PREMISES CHECKED AND FOUND WRONG
The batch's items were implemented as written where the evidence supported them and **corrected where it did not**. Each of these is recorded in the code comments and in the CHANGELOG.

1. **M6 / `FauxScrollFrame_Update` "returns NOTHING" — FALSE.** The function starts at `SecureScrollTemplates.lua:158` and ends at **:224** with `return showScrollBar;` on all five branches; the audit cited the range "158-222", which stops two lines short of the return. The real arity is **1** (1 when there is more than one screen of items, nil otherwise). The Extras mock already published exactly that, so **the mock was NOT changed** — changing it to the audited shape would have made it *less* faithful. The CONTRACT is what was corrected (`realArity = 1`, `mockArity = 1`), and the Extras harness now asserts it.
2. **N2 / "`GameTooltip.FadeOut` exists only on live and forever" — FALSE.** `GameTooltip.FadeOut` is an ENGINE method: it has no Lua definition on any branch (and is absent from the generated API docs on all five), so a whole-tree sweep cannot prove it absent — the repo's own harness README already says so ("Absence of a consumer is not absence of an API"). Blizzard CALLS it on **all five**: `Blizzard_UnitFrame/Classic/UnitFrame.lua:447` on the three Classic branches, `Blizzard_UnitFrame/Mainline/UnitFrame.lua:393` (forever) and `:386` (live) — and on the Classic family `UnitFrame_OnLeave` is wired to the `OnLeave` of `PlayerFrame.xml:374` and `TargetFrame.xml:380`, so the call runs on every mouse-out. **Consequence:** the item's fix is implemented as a **runtime capability probe** (`type(GameTooltip.FadeOut) == "function"`), not a client-family table. On every supported client the method is present, so the checkbox stays enabled and the option behaves exactly as before; the checkbox is disabled + explained only on a client that genuinely lacks the method, and `/tacotip diag` prints the mode. Disabling the option on the Classic family would have removed a **working** feature from 112k users' clients.
3. **N5 / "`CanInspect` is absent from the generated API docs on all five branches and has no upstream consumer" — FALSE.** It IS documented: `Blizzard_APIDocumentationGenerated/PlayerScriptDocumentation.lua:54` on the three Classic branches and `:55` on forever/live, with one argument (`targetGUID`, Type "UnitToken") and one return (`result`, bool) — so the library's original claim ("documented with a single argument on every branch") was CORRECT and its reasoning was simply uncited. And it HAS upstream consumers on every branch: `InspectFrame_Show`'s `CanInspect(unit, true)` on all five, plus the single-argument `CanInspect(contextData.unit)` at `Blizzard_UnitPopupShared/UnitPopupSharedButtonMixins.lua:293/:318` on forever/live. The comment now carries the citation (and the note that the second argument is NOT in the documented signature — which is why this file never passes it). **Behaviour untouched.**
4. **N6 / "`C_Map.GetBestMapForUnit` is modern-only" — FALSE.** It is documented and used by Blizzard on every branch (`Blizzard_APIDocumentationGenerated/MapDocumentation.lua` and `Blizzard_FrameXMLUtil/Classic/MapUtil.lua:57` on the Classic family). What IS true on every branch is its documented contract — "Only works for the player and party members" — so the "target is on another map" suppression can only ever fire for a group or raid member, on ANY client. The comment now says that, so a maintainer does not read the nil guard as a Classic-only workaround.

## 2026-10-19 — IMPLEMENTATION

### Item 1 (H1) — character / inspect pane refresh (`main.lua`)
- `TT:InitCharacterFrame()`: the dead `PaperDollFrame:HookScript("OnShow", TT.RefreshCharacterFrame)` is replaced by `_G.CharacterFrame:HookScript("OnShow", ...)`, guarded for nil. **The handler is an adapter** — a `HookScript` handler is called as `handler(frame)`, so the method would have received the FRAME as `self` (the old hook would have raised had it ever fired).
- `TT:InitInspectFrame()`: the dead `InspectPaperDollFrame:HookScript("OnShow", ...)` is replaced by `_G.InspectFrame:HookScript("OnShow", ...)`. The existing `InspectFrame:HookScript("OnHide", ...)` is untouched.
- `TacoTip_GSCallback(guid)`: a new path repaints the OPEN character pane when the guid is the player's own. It is placed **before** the re-entrancy guard on purpose (the guard drops a nested call for the guid already being serviced, and the pending value is only replayed for a DIFFERENT guid, so a nested player callback would be lost). The tooltip-pipeline path is unchanged — every non-player guid is still dropped exactly as before.
- `characterPaneReadyBudget`: one pending→ready repaint per pane open, so a burst of item-load callbacks cannot become one inventory walk each (the 0.8.2 bug was EIGHT walks for one open). The budget is set to 1 by the pane's OnShow handler.
- Guardrails held: exactly ONE inventory walk per pane open; `InCombatLockdown()` still guards the inspect refresh; the refresh reads cached data only and issues no inspect request (`CI:GetInventoryItemMixin` reads `GetInventoryItemLink` for the player and the library's cache for anyone else).

### Item 2 (N2) — instant fade (`options.lua`, `main.lua`)
- `instantFadeSupported()` — a runtime capability probe. `updateInstantFadeState` records `"unsupported"` when the API is absent, `"secure-hook"` when the hook is installed, `"standard-fade"` when the option is off.
- The checkbox is built disabled + explained (`controls.instantFade.description`, a plain English FontString — **no locale key**, because the Locale files are not touched by this change and the harness asserts every locale key used by the source exists in the locale table) when the API is absent.
- `/tacotip diag` prints `instant fade: <mode>` and `instant fade API: <type>`.

### Item 3 (N4) — options loader (`options.lua`)
- `OPTIONS_LOAD_ABSENT_ON` — a mirror-verified, branch-qualified applicability table. `optionsLoadTargetApplicable(which)` returns false for a target that does not exist on the detected family; `optionsLoadAddOn` then returns without calling `LoadAddOn` and without counting a failure. An **unknown** family treats every target as applicable (fail loud). A client-appropriate target that fails to load still counts and still surfaces.

### Item 4 — mock fidelity + the contract
- New `Tests/harness/mock_contract.lua`: the data-driven table (`api`, `realArity`, `mockArity`, `source`, `owner`, `probe`) plus `setFamily` / `normaliseFamily` / `expected` / `measure` / `assertArity` / `unitClassMock`.
- Mocks corrected: `UnitClass` is now per-family (3 on the modern pair, 2 on the Classic family) in `tooltip_test`, `load_test`, `options_test`, `settings_test`, `taint_test`, `batch4_clock_test`, `talent_check` **and in the Extras `load_test.lua`** (its base mock published two on every client; the two later overrides published three, including on the Classic family). `GetSpecializationInfoByID` now publishes 7 values in `tooltip_test`, `detect_test`, `fileguard_test` **and in the Extras `rankbrowser_test.lua`** (both mock sites).
- Contract assertions added to the nine MAIN harnesses that own a contract API, plus the Extras `rankbrowser_test.lua` (both Extras arities) and the Extras `load_test.lua` (`UnitClass`).
- The `GetSpecializationInfoByID` probe had to be a REAL spec id (71): a probe that missed would have measured the not-found branch's arity and could not see a mock that only lost a value on the found branch. Caught by the revert proof.
- The Extras harnesses load the shared table from `ROOT .. "/../Tests/harness/mock_contract.lua"` (loudly — a missing file raises). Both use a one-line `contractCheck` adapter because their `check()` takes `(cond, label, detail)` and the shared helper takes the MAIN order `(name, cond, detail)`. The adapter in the Extras `load_test.lua` had to be defined **after** `check()`, because it closes over it — defining it before produced `attempt to call global 'check' (a nil value)` at the load.
- `MOCKC.normaliseFamily` gained the `classic_era` spelling the Extras harness uses (the MAIN harnesses use `CLASSIC_ERA`).
- **No Extras PRODUCTION code was touched**: `RankBrowser.lua`, `Tooltips.lua`, `Frames.lua`, `Scoring.lua`, `RankDB.lua`, `RankSync.lua`, `Scanner.lua`, `Core.lua`, `TacoTipAdapter.lua` and `TacoTip_Extras/Locale/` all keep their pre-session mtimes. Only `TacoTip_Extras/Tests/harness/rankbrowser_test.lua` and `TacoTip_Extras/Tests/harness/load_test.lua` were edited.
- The Extras `UnitClass` correction is behaviourally inert for the Extras add-on: the only readers of `UnitClass` there take positions #1 and #2 (`Frames.lua:274`, `Scanner.lua:360`, `Tooltips.lua:383`); the third value (the class ID) is never read.

### Item 5 — doc corrections (comments only)
- `LibForeverInspector`: the `CanInspect` comment now carries the API-doc citation and states what was actually verified (including that the probe returns nil and every call site is guarded when the API is absent).
- `main.lua`: the "target is on another map" suppression records the true, all-five-branches fact about `C_Map.GetBestMapForUnit`.
- `main.lua`: the HunterScore line records the OPERATOR'S DECISION (the GearScore band colour is intentional; not a defect; must not be "fixed").

### Item 6 — CHANGELOG / README
- `CHANGELOG.md`: a `### Batch 8` subsection under the existing `## [0.8.4]` (no version bump, 0.8.3 and earlier untouched, Batches 1-7's substance untouched).
- `README.md`: two plain-language lines in "What's New in 0.8.4" (the pane no longer sits on 0; the instant fade is explained where the client cannot do it). No jargon, no batch names.
- `Tests/harness/README.md`: the mock-fidelity table's `FauxScrollFrame_Update`, `UnitClass` and `GetSpecializationInfoByID` rows corrected; the invocation count 64 → 70; the new harness documented.

## 2026-10-19 — Validation (all green, all three interpreters)
- MAIN `bash Tests/harness/run_all.sh`: **70/70** on lua5.1, lua5.4, luajit (64 before this batch: +5 `batch8_pane_test` invocations, +1 `options_test no instant-fade API`).
- Extras `bash TacoTip_Extras/Tests/harness/run_all.sh` (no `LUA` override → the script runs all three interpreters): **TOTAL 42 invocations: 42 passed, 0 failed**. (`LUA=<interp>` runs exactly one interpreter = 14 invocations; 14 × 3 = 42.)
- `luacheck .` from the repo root: **0 warnings / 0 errors in 87 files** (85 before: +`mock_contract.lua`, +`batch8_pane_test.lua`).
- `cd TacoTip_Extras && luacheck .`: **0 warnings / 0 errors in 26 files**.
- Check counts: `batch8_pane_test` 27 checks per client; `options_test` 33 → 50 (settings=on) / 33 → 37 (nosettings); `settings_test` 71 → 76 (nosettings); `tooltip_test` 169 → 171 (Classic) / 170 → 172 (pipeline); `load_test` +1; `talent_check` +1 printed line; Extras `rankbrowser_test` 271 → 273 (two contract pins); Extras `load_test` +1 per client.

### Revert-to-fail proofs (all three interpreters)
| # | reverted | red |
|---|---|---|
| 1 | character hook → the dead `PaperDollFrame` hook | 6/27 (`hook=nil`, `walks=0`) |
| 2 | pending→ready path removed from `TacoTip_GSCallback` | 2/27 |
| 3 | inspect hook → the dead `InspectPaperDollFrame` hook | 3/27 |
| 4 | `"unsupported"` mode → `"standard-fade"` | 2/27 |
| 5 | the diag lines removed | 1/27 |
| 6 | the disabled+explained checkbox removed | 2/37 (`enabled=true`, `desc=nil`) |
| 7 | the checkbox disabled UNCONDITIONALLY (wrong direction) | 2/50 (`enabled=false`) |
| 8 | the N4 applicability rule removed | 3/76 (the counter moved; all six targets attempted) |
| 9 | everything treated as non-applicable (wrong direction) | 5/76 |
| 10 | the two-value `UnitClass` mock restored | 1/172 (`mockArity=2 contract=3`) |
| 11 | the four-value `GetSpecializationInfoByID` mock restored | 1/171 (`mockArity=4 contract=7`) |
| 12 | the Extras `FauxScrollFrame_Update` mock made a true no-return | 1 (`mockArity=0 contract=1`) |
| 13 | the Extras `GetSpecializationInfoByID` mock restored to four values | `FAIL mock GetSpecializationInfoByID publishes 7 values … mockArity=4 contract=7` — 1, exit=1 |
| 14 | the Extras `load_test` `UnitClass` mock restored to the flat two-value form | `FAIL mock UnitClass publishes 3 values … mockArity=2 contract=3` on retail/forever, exit=1 |

Every revert was restored byte-identical from a copy taken before the proofs.

### Constraint compliance
- **No `CanInspect(unit, true)` anywhere in the shipped code** — the only live call is `pcall(api, unit)` at `LibForeverInspector.lua:4895` (single argument). The two-argument form appears only in COMMENTS describing Blizzard's own call, and in the stale `OLD/Libs/LibClassicInspector/` copy (not in the TOC).
- **Range gate FROZEN** — `NEARBY_ASK_YARDS = isClassic and 20 or 40` (`:414`) and `INSPECT_INTERACT_DISTANCE_INDEX = 1` (`:396`) unchanged; `Libs/` touched for comments only.
- **Raw GearScore formula UNTOUCHED** — `gearscore.lua` not modified by this desk; the Retail bracket still holds at the shared 1000.
- **Guild/level line-index ownership proof untouched** — `TacoTipGuildLineIndex` / `TacoTipGuildLineText` / `TacoTipLevelColorLineIndex` / `TacoTipLevelColorLineText` (`main.lua:558-582`) unchanged.
- **`CharacterModelFrame` never indexed unguarded** — only `_G.CharacterModelFrame or _G.PaperDollFrame` (`:3496`).
- **Locale files untouched** — the only diff is the orchestrator's 10 → 12 font size in all 11 locale files (pre-existing).
- **No Extras production code touched** — `RankBrowser.lua`, `Tooltips.lua`, `Frames.lua`, `Scoring.lua`, `RankDB.lua`, `RankSync.lua`, `Scanner.lua`, `Core.lua`, `TacoTipAdapter.lua` and `TacoTip_Extras/Locale/` keep their pre-session mtimes; only the two Extras TEST files were edited.
- **No `*.toc`/version changes; no bench/ or other-desk writes; no commit; no staging** (`git diff --cached` empty).

## 2026-10-19 — [signal:done] Batch 8 complete
- **Worked on:** item 1 (H1 character/inspect pane refresh + pending→ready repaint), item 2 (N2 instant-fade capability probe + diag line + disabled/explained checkbox), item 3 (N4 options-loader applicability), item 4 (mock corrections + the executable contract, **MAIN and Extras harnesses**), item 5 (doc corrections + the operator's HunterScore decision), item 6 (CHANGELOG + README).
- **Current state:** all six items implemented, pinned and revert-proven; MAIN **70/70** and Extras **42/42** on lua5.1 / lua5.4 / luajit; lint 0/0 in 87 + 26 files. No commit, no staging. No Extras production code touched.
- **Next step:** operator review. **Three audit premises were found wrong and the implementation was corrected rather than followed** (the `FauxScrollFrame_Update` arity, the `GameTooltip.FadeOut` existence on the Classic family, and the `CanInspect` API-doc entry) — see the journal entry above and the CHANGELOG. Still open and NOT addressed here: the H2 tri-state contract call (operator decision owed), the M7/L-NEW1 ruRU spec-name placeholders (translator needed), and the whole structural refactor set.
