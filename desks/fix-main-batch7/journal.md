# fix-main-batch7 — Journal

## 2026-10-19 — Desk opened
- **Purpose:** Fix 5 orchestrator-verified defects in MAIN TacoTip + TacoTip_Extras (Batch 7). No commit, no staging. Every fix revert-to-fail proven in-harness.
- **Scope:** `main.lua`, `TacoTip_Extras/RankBrowser.lua`, `TacoTip_Extras/Tests/harness/*.lua` (pins only), `Tests/harness/*.lua` (pins only), `CHANGELOG.md` + `TacoTip_Extras/CHANGELOG.md` (append to existing [0.8.4] / [1.2.3] sections, no version bump), `desks/fix-main-batch7/`. NOT `gearscore.lua`'s formula, NOT `Libs/`, NOT `*.toc`, NOT `README.md`, NOT `bench/`, NOT other desks.
- **Constraints:** Classic Era inspect range gate FROZEN; raw GearScore formula UNTOUCHED; Retail bracket HOLD at shared 1000; no invented Russian strings; no `*.toc`/version changes; no bench/ or other-desk writes.
- **Baselines (read from source, re-run before first edit):** MAIN `bash Tests/harness/run_all.sh` = **64/64** (lua5.1); Extras `bash TacoTip_Extras/Tests/harness/run_all.sh` = **42/42**.
- **Bench-read:** `desks/publish-hunter` (hunter audit, 4 HIGH / 6 MEDIUM / 5 LOW — this batch's items are the follow-on findings it did not cover), `desks/fix-main-batch6` (prior batch; its `MAX_STATIC_POPUP_DIALOGS` citation is the one item 5a corrects), `bench/audits/2026-10-19-publish-readiness-hunter.md`. No `desks/main-arbiter` or `desks/proctor-audit` present.

## 2026-10-19 — Mirror evidence collected (all five branches)
Source: `/home/sam/wow-ui-source` (read-only). Branches: `origin/classic_era`, `origin/classic_anniversary`, `origin/classic_titan`, `origin/forever`, `origin/live`.

### Item 1 — INVTYPE_* slot-label globals
- `INVTYPE_HANDS` — **exists in NONE of the five branches** (`git grep -c "INVTYPE_HANDS" <branch>` → no match on all five).
- `INVTYPE_HAND` — **exists in ALL FIVE**: `origin/classic_era` / `origin/classic_anniversary` / `origin/classic_titan` / `origin/live` → `Interface/AddOns/Blizzard_EncounterJournal/Cata/Blizzard_EncounterJournal.lua:126` (`[Enum.ItemSlotFilterType.Hand] = INVTYPE_HAND`); `origin/forever` → `Interface/AddOns/Blizzard_EncounterJournal/Mainline/Blizzard_EncounterJournal.lua:176`.
- All 15 distinct INVTYPE names used by `SLOT_ROWS` (HEAD, NECK, SHOULDER, CLOAK, CHEST, WRIST, **HAND**, WAIST, LEGS, FEET, FINGER, TRINKET, WEAPONMAINHAND, WEAPONOFFHAND, RANGED) → present on all five branches.
- `INVTYPE_CLOAK` → `.../Blizzard_EncounterJournal/Cata/Blizzard_EncounterJournal.lua:123` (classic_era/anniversary/titanforge), `.../Mainline/Blizzard_EncounterJournal.lua:173` (forever), `.../Cata/Blizzard_EncounterJournal.lua:123` (live). Its English string is "Back" — the back slot keeps `INVTYPE_CLOAK`.

### Item 4-addition — GetItemInfoInstant is namespaced-only on Retail/Forever
- Bare global `GetItemInfoInstant` call sites: **0 on all five branches** (`git grep -E '(^|[^._[:alnum:]])GetItemInfoInstant[[:space:]]*\('` excluding `C_Item.GetItemInfoInstant`). Namespaced `C_Item.GetItemInfoInstant` present on all five.
- The bare global exists only where `Interface/AddOns/Blizzard_DeprecatedItemScript/Deprecated_ItemScript.lua:10` aliases it: `GetItemInfoInstant = C_Item.GetItemInfoInstant;` — present on `origin/classic_era`, `origin/classic_anniversary`, `origin/classic_titan`. **File absent on `origin/forever` and `origin/live`.**
- Blizzard's own use of the namespaced form: `origin/classic_era:Interface/AddOns/Blizzard_AuctionHouseUI/Shared/Blizzard_AuctionHouseSharedTemplates.lua:366` → `local itemID = C_Item.GetItemInfoInstant(itemLink);` (first return = item ID). `origin/classic_era:Interface/AddOns/Blizzard_ObjectAPI/Classic/Item.lua:98-100` → `function ItemMixin:GetItemID() ... return (C_Item.GetItemInfoInstant(self:GetStaticBackingItem()));` (same first-return contract). `origin/forever` / `origin/live`: `Interface/AddOns/Blizzard_ObjectAPI/Mainline/Item.lua:159` → `return C_Item.GetItemInfoInstant(backingItem) or ...`.

### Item 5a — StaticPopup pool
- `Interface/AddOns/Blizzard_StaticPopup_Game/GameDialog.xml` declares `name="StaticPopup1..4"` (ids 1..4) on **all five** branches: lines **334/339/344/349** on classic_era, classic_anniversary, classic_titan, live; lines **339/344/349/354** on forever. `StaticPopup5` matches **nowhere** on any branch → "and no fifth" holds.

### Item 5b — strata of the two offending frames
- `Interface/AddOns/Blizzard_GameMenu/Shared/GameMenuFrame.xml` → `<Frame name="GameMenuFrame" ... toplevel="true" frameStrata="DIALOG" ...>` on **all five**: line **4** on classic_era, classic_anniversary, classic_titan, live; line **7** on forever (that file has an extra `GameMenuFrameButtonTemplate` button at line 4).
- `Interface/AddOns/Blizzard_Settings_Shared/Blizzard_SettingsPanel.xml` → `<Frame name="SettingsPanel" ... toplevel="true" ... frameStrata="HIGH">` on **all five**, line **4** in every branch.

## 2026-10-19 — Decisions taken before editing
- **Item 2 helper home: local helper in `main.lua`.** `pawn.lua` already has the `tonumber`-guarded `pawnVersionAtLeast` (`pawn.lua:27-30`) but it is **file-local — NOT exposed** on `TT_PAWN` (only `WasAvailableAtLoad` and `IsAvailable` are). Exposing it would mean editing `pawn.lua`, which is **outside this batch's stated SCOPE** (main.lua, RankBrowser.lua, both harnesses, both CHANGELOGs, this desk). `main.lua` also loads **last** (`TacoTip.toc`: gearscore → pawn → textures → options → main), but `pawn.lua` can fail to load independently (`assert(LibStub)` at `pawn.lua:47-49`), so a `TT_PAWN`-dependent probe would be less safe, not more. A local helper is the alternative the item text names explicitly. Semantics copied verbatim from `pawn.lua:27-30`: non-numeric → treated as absent → probe falls through to the API-present fallback.
- **Item 1 testability:** `SLOT_ROWS` / `slotLabel` are file-local in `RankBrowser.lua`, so the harness cannot reach them. The label path is made observable through the *rendered panel text* (the gear panel already renders `slotLabel(spec) .. ":  " .. value` / `"|cff808080" .. slotLabel(spec) .. "|r"`), which is the user-visible surface — no new production surface needed for the render pins. The **17 global names** are pinned through a debug-only accessor (`RankBrowser.GetDebugState().slotRows`), following the batch-6 `GetDebugState` precedent (`RankBrowser.lua:607-612`); read-only, no display or behaviour change.
- **Item 3 detector shape:** swap detection = first argument is a `string` AND second argument is a `boolean`. No existing Extras harness call matches that shape (verified by scan), so the detector cannot fire on legitimate calls.

## 2026-10-19 — IMPLEMENTATION (all five items) + pins

### Item 1 — INVTYPE_HANDS → INVTYPE_HAND (`TacoTip_Extras/RankBrowser.lua:1089-1107`)
- Row 7 (slot 10) now names `INVTYPE_HAND`, fallback `"Hand"`. `INVTYPE_CLOAK` (slot 15, English "Back") kept.
- The comment above the table now cites all five branch names + file:line (replacing "classic_era anniversary / titanforge").
- **Testability:** `RankBrowser.GetSlotRows()` (`RankBrowser.lua:1119-1126`) exposes the 17 rows read-only — debug only, no display/behaviour change (batch-6 `GetDebugState` precedent). The 17 rows use **15 distinct** globals (FINGER and TRINKET are each named twice), so the mock defines 15 and the pins cover all 17 rows.
- **Pins** (`TacoTip_Extras/Tests/harness/rankbrowser_test.lua`): the 15 client globals are defined in the mock with marker values (`SLOTLABEL_*`) that are deliberately **not a real language** (no invented translations). (a) the translated global is used when present; (b) the English fallback when absent (`_G.INVTYPE_HAND = nil` → the row renders `Hand:  item:2222`); (c) all 17 rows pinned against the expected ordered (slot, global, fallback) list AND against the set of globals the client publishes. 5 new checks.
- **Revert proof:** `INVTYPE_HAND` → `INVTYPE_HANDS` → **5/270 red** on lua5.1/5.4/luajit (name pin, hand-row pin, (a), "every row takes its own client global", (b)). Restored byte-identical.

### Item 2 — Pawn probe guard (`main.lua:134-183`)
- Local `pawnVersionAtLeast(raw, threshold)` + `PAWN_CLASSIC_MIN_VERSION`/`PAWN_RETAIL_MIN_VERSION`, semantics copied verbatim from `pawn.lua:27-30` (non-numeric → absent → falls through to the API-present fallback).
- **Home choice: local to `main.lua`** (the item's sanctioned alternative). `pawnVersionAtLeast` is file-local in pawn.lua and NOT exposed on `TT_PAWN`; pawn.lua is outside this batch's SCOPE; and main.lua loads last but pawn.lua can fail to load on its own (`assert(LibStub)`, `pawn.lua:47-49`) — a `TT_PAWN`-dependent probe would be less safe, not more.
- **CHANGELOG corrected:** the Batch-5 sentence "A string-typed version global no longer raises **on any probe**" now reads "…no longer raises **on the `pawn.lua` and `options.lua` probes** — `main.lua`'s own file-scope probe was NOT covered by that change and is fixed in Batch 7 below." The claim was false before this batch.
- **Pins** (`Tests/harness/load_test.lua`): a **whole-add-on second load** after every other check is collected, with both Pawn version globals hostile (non-numeric strings) AND the API trio removed. The API trio must go too, or `isPawnLoaded` is true and the live re-probe is short-circuited (`not isPawnLoaded and isPawnAvailableNow()`) and never runs. 3 new checks: the load completes, `LOAD_OK == true`, and `/tacotip diag` (which reaches the live probe) does not raise.
- **Revert proof:** site 1 (the file-scope snapshot) restored to the raw compare → **3 checks red**, `main.lua:166: attempt to compare number with string`, on all three interpreters. Site 2 (the live re-probe) restored with site 1 intact → **1 check red**, `main.lua:180: attempt to compare number with string`, on all three interpreters. Restored byte-identical (`diff` vs backup clean).

### Item 4 — shared throttle + namespaced item ID (`main.lua:212-263`, `main.lua:2816-2822`)
- `RequestLoadItemDataByID` is now a local wrapper: `TT_GS.RequestLoadItemDataByID` when present (resolved at CALL time), the raw `C_Item` call only when TT_GS is absent (gearscore.lua failed to load — not a valid state).
- `getItemInfoInstantID(itemLink)` resolves `C_Item.GetItemInfoInstant` (captured at file scope) with the bare global as a fallback only for a client with no `C_Item` namespace; the FIRST return is the ID, and it must be a number.
- **Pins** (`Tests/harness/tooltip_test.lua`): the item-data request counter is installed **before** the load (gearscore.lua captures `C_Item.RequestLoadItemDataByID` at file scope, gearscore.lua:101 — a counter swapped in later would never be seen by the throttle); the namespaced resolver reads its value at CALL time through a harness variable. 5 new checks: the cold path runs with **no** bare global; exactly **one** request; it carries the **numeric** ID 98765; a rapid second request for the same item is throttled to **one** raw call; the window expiring re-requests.
- **Revert proof:** raw `C_Item` call restored (throttle bypassed) → **2/160 red** (`requests=2`, `requests=3`) on all three interpreters. Bare read restored → **4/160 red** (`requests=0`) on all three interpreters. Restored byte-identical.

### Item 3 — swapped-argument guard (both Extras harnesses)
- `isSwappedCheckArgs(first, second)` = first is a string AND second is a boolean. Both `check()` implementations fail LOUDLY on that shape, record a failure (so the suite goes red) and never take the PASS path. No legitimate call in either harness matches the shape — proven by the suite staying green.
- **Pins:** a deliberately swapped call is made through a captured-output probe, must return false, must record a failure, must not advance PASS, and must produce loud output; the probe's own failure is then removed so the pin cannot turn the suite red. The probe is `pcall`'d because with the guard absent the call does not merely pass — it concatenates a boolean label and raises, which would take the harness down with it.
- **Revert proof:** guard disabled in `rankbrowser_test.lua` → **1/270 red** with the detail naming the boolean-label concat; guard disabled in Extras `load_test.lua` → **1/421 red**, on all three interpreters. Restored.

### Item 5 — branch-qualified mirror citations (comments only)
- `main.lua` `MAX_STATIC_POPUP_DIALOGS`: all five branches named, with the `origin/forever` line offset (`:339-354` vs `:334-349`) and the "StaticPopup5 matches nowhere" fact.
- `TacoTip_Extras/RankBrowser.lua`: `GameMenuFrame` (all five, `:4`, `:7` on forever) and `SettingsPanel` (all five, `:4`).
- No behaviour change; nothing to revert.

### CHANGELOG
- MAIN: new `### Batch 7 — …` section under `[0.8.4]` (5 items + the Batch-5 correction). No version bump, no TOC change.
- Extras: new Batch-7 section under `[1.2.3]` (item 1 + citations + harness guard). No version bump, no TOC change.

## 2026-10-19 — Validation (all green, all three interpreters)
- MAIN `bash Tests/harness/run_all.sh`: **64/64** on lua5.1, lua5.4, luajit.
- Extras `bash TacoTip_Extras/Tests/harness/run_all.sh`: **42/42** total (14 per interpreter × 3), green on all three.
- `luacheck .` from the repo root: **0 warnings / 0 errors in 85 files**.
- `cd TacoTip_Extras && luacheck .`: **0 warnings / 0 errors in 26 files**.
- Suite runtime 3.80s → 3.96s (the whole-add-on second load adds ~0.16s across all 64 invocations).
- **Constraints:** range gate FROZEN (`Libs/` untouched by this desk; `CheckInteractDistance`/`inspectRangeLimit` identifiers verified present); raw GearScore formula UNTOUCHED (`gearscore.lua` not modified by this desk; `BRACKET_SIZE` still 1000 default with the Retail hold at the shared 1000 — `gearscore.lua:179,193`); ruRU untouched by this desk (no invented strings anywhere); no `*.toc`/version changes; no `bench/` or other-desk writes; no commit, no staging (`git diff --cached` empty).
- **Concurrent-workspace note (not this desk's work):** at 19:33 another process modified every `Locale/*.lua` and `TacoTip_Extras/Locale/enUS.lua` (a font-size 10→12 tweak) and created `bench/audits/2026-10-19-test-sufficiency-audit.md` at 19:24. This desk did not touch those files; both suites were re-run after that timestamp and are green.

## 2026-10-19 — [signal:done] Batch 7 complete: 5 verified defects fixed, pinned, revert-proven
- **Worked on:** item 1 (INVTYPE_HAND + label path made testable), item 2 (Pawn file-scope probe guard + CHANGELOG correction), item 3 (Extras harness swapped-argument guard), item 4 (shared throttle + namespaced `C_Item.GetItemInfoInstant`), item 5 (branch-qualified mirror citations).
- **Current state:** all five items implemented, pinned and revert-proven; both suites green on lua5.1/5.4/luajit; lint 0/0 in 85 + 26 files. No commit, no staging.
- **Next step:** operator review. Not done here: the `H2` tri-state decision and the `L-NEW1`/`M7` ruRU spec-name placeholders, which remain open from the publish-hunter audit and are out of this batch's scope.

## 2026-10-19 — SECOND ADDITION to item 4: two harness mock corrections

### (a) `GameTooltip:GetUnit` was mocked with a THIRD value the engine never returns
**Mirror evidence** (all five branches): Blizzard's own call sites destructure exactly two — `local name, unit = self:GetUnit()` at `Interface/AddOns/Blizzard_PTRFeedback/Blizzard_PTRFeedback_Tooltips.lua:87` (classic_era / classic_anniversary / classic_titan) and `:105` (forever / live). **No call site on any branch destructures three** (`git grep -E "local [^,]+,[^,]+,[^=]+=\s*[^ ]*\.?GetUnit\(\)"` → no match on any branch). The GUID comes from the SIBLING resolver: `Interface/AddOns/Blizzard_SharedXMLGame/Tooltip/TooltipUtil.lua:40` → `return name, unit, guid;` — and that namespace does not exist on the Classic family.

**Production read** (`main.lua:1134`): `local ok, _, tooltipUnit, guid = pcall(tooltip.GetUnit, tooltip)` — the third value is **always nil on a real client**. The `elseif (ok and guid)` arm can only run when GetUnit published NO token, and in that case there is no guid either → **the arm is unreachable on every supported client**.

**Change** — `Tests/harness/tooltip_test.lua`: a `mockGetUnit(unitToken)` helper (returns exactly two values) replaced **13** three-value mock sites; the base mock at `:930` was already faithful. Three more harnesses published an explicit `nil` third value (`batch4_clock_test.lua:187`, `options_test.lua:390`, `load_test.lua:350`) — behaviourally identical, but the arity was still a fiction → made two-value. `main.lua` gained a **comment only** at the guid arm documenting the unreachability and the mirror evidence (no behaviour change; the arm is left in place, harmless, and documented).

**Pins** — 9 new checks:
- arity pin, next to the resolver the whole Classic suite runs on (`installUnitResolver`): the installed mock publishes exactly **two** values.
- **the real Classic chain**, arm by arm, observed through `TacoTip_GSCallback` (which resolves with NO unit argument — `main.lua:1463` — and compares the resolved unit's guid against the one it was handed): (1) a token that EXISTS but that `IsUnit` disagrees about falls through to the **GetOwner** arm; (2) the **"mouseover" last resort** is taken only when the tooltip really is the mouseover tooltip; (3) nothing resolving counts the failure and names the cause `unresolved`; (4) a GetUnit that publishes **NO token at all** still resolves through the owner — the proof the addon does not depend on the guid arm.
- **Revert proofs:** the three-value mock restored → the arity pin red (`returns=3`), 1/169 ×3. The guid fiction restored (mockGetUnit publishing a third value) → **3/169 red** ×3: the arity pin, plus both no-token pins — the guid arm firing and resolving to the wrong unit. That is the exact difference between the fiction and the real client.

### (b) The `Settings` namespace was mocked with a phantom self
**Mirror evidence** (all five branches), `Interface/AddOns/Blizzard_Settings_Shared/Blizzard_Settings.lua`: `:133`/`:134` `function Settings.RegisterAddOnCategory(category)`, `:143`/`:144` `function Settings.OpenToCategory(categoryID, scrollToElementName)`, `:161`/`:162` `function Settings.RegisterCanvasLayoutCategory(frame, name)`, `:165`/`:166` `function Settings.RegisterCanvasLayoutSubcategory(parentCategory, frame, name)` — all plain dot-called, no self. Production matches exactly: `options.lua:783` `RegisterCanvasLayoutCategory(optionsFrame, optionsFrame.name)`, `:785` `RegisterAddOnCategory(addOnOptionsCategory)`, `:724-725` `pcall(RegisterCanvasLayoutSubcategory, addOnOptionsCategory, spec.page, spec.page.name)`.

**Change** — `Tests/harness/options_test.lua`: the mock's `registered` table (never asserted — 6 grep hits, all definitions) became a `settingsLog` that IS asserted, and the phantom self and the wrong arity are gone. The category call now returns a **category OBJECT** (`{ID=, name=, frame=}`) like the client's, not the name string the phantom-self mock produced — which also means `addOnOptionsCategory.ID` is now meaningful and the `OpenToCategory` path is exercised for real.

**Pins** — 13 new checks: the category registered exactly once with the FRAME in the first slot and the NAME in the second, and the frame is the add-on's own `TacoTipOptions` frame; the add-on category registered exactly once and is the category OBJECT (not the name string); the three pages registered as subcategories with the CATEGORY as parent, the PAGE FRAME in the middle slot and the NAME in the last; the panel opened by the category's ID. The `nosettings` variant registers nothing and skips them all — that is what the variant is for.
- **Revert proof:** the phantom-self mock restored → **7/46 red** ×3, naming the mis-shaped slots (`frame=string name=nil`, `parent=Tooltips`, `count=0`).

### Validation after the second addition
- MAIN `bash Tests/harness/run_all.sh`: **64/64** on lua5.1, lua5.4, luajit. Extras: **42/42** (14 per interpreter × 3).
- `luacheck .` (repo root): **0 warnings / 0 errors in 85 files**. `cd TacoTip_Extras && luacheck .`: **0 warnings / 0 errors in 26 files**.
- `tooltip_test.lua` check counts: 160 → **169** (Classic) / **170** (pipeline). `options_test.lua`: 33 → **46** (settings=on) / **33** (nosettings).
- **Constraints unchanged:** no production behaviour change (the only `main.lua` edit in this addition is a comment); range gate, formula and Retail bracket untouched; no `*.toc`/version changes; no `bench/` or other-desk writes; no commit, no staging.


