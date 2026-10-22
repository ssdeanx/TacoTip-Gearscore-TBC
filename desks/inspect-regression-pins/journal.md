# inspect-regression-pins — Journal

## 2026-10-20 — Desk opened
- **Purpose:** add the missing OFFLINE harness pins for the **0.7.9 right-click inspect regression**, so the guarantee is provable without a live client. The operator cannot test it in game before publishing, so the suite has to stand in for that test.
- **Scope:** `Tests/harness/*.lua` ONLY (pins + the mock stubs they need). No production file (`main.lua`, `options.lua`, `gearscore.lua`, `pawn.lua`, `textures.lua`, `Libs/**`, `TacoTip_Extras/**`), no changelogs, no docs, no `.toc`s. No new files except this desk.
- **Spec:** `CHANGELOG.md` 0.7.9 — "Right-click inspect stripped all gear from the paperdoll on Retail and WoW Forever" (`:701`), and `bench/audits/2026-10-20-inspect-and-guild-line-history.md` (the trap that keeps coming back).
- **Pins wanted:** P1 the `ClearInspectPlayer` absence (the 0.7.9 bug itself), P2 the `InspectFrame.unit` fallback (right-click inspect of a non-targeted party/raid member), P3 the guild guard's install path (may already exist).
- **Next step:** read the tree, find where the inspect path is driven, add the pins with revert-to-fail proofs on COPIES.

## 2026-10-20 — Desk opened: what the tree already holds
- **P3 ALREADY EXISTS.** `Tests/harness/tooltip_test.lua:3317` pins "the guild guard installs when Blizzard_InspectUI loads (modern pair)" and `:3325` pins "the guild guard is a NO-OP on the Classic family (no global to wrap)", plus the swallow and the two buckets. Do NOT duplicate it.
- **P1 is currently unpinnable.** `ClearInspectPlayer` has ZERO call sites in shipped code (grep over the whole repo: only `CHANGELOG.md`, `README.md`, `bench/`, `desks/` and the harness mocks). The harness mocks it as a plain no-op (`REALG.ClearInspectPlayer = function() end` in seven files), so nothing records the call and nothing can go red if it comes back.
- **The 0.7.9 bug shape:** `ClearInspectPlayer()` purges the inspected unit from the client engine, so Blizzard's own `InspectPaperDollItemSlotButton_Update` reads a nil `GetInventoryItemTexture` for all 18 equipment slots and the paperdoll renders EMPTY. The fix IS the absence of the call — so only a counter can prove it.
- **Where the inspect path is driven:** `Tests/harness/detect_test.lua` (the real `LibForeverInspector`, `INSPECT_READY` → `cacheUnitData`, cache asserted) and `Tests/harness/tooltip_test.lua` (the same handler, on all five clients — including RETAIL and FOREVER, the two clients 0.7.9 broke).
- **Next step:** make the `ClearInspectPlayer` mock record its calls, add P1 and P2, then prove each red on a copy.

## 2026-10-20 — P1 and P2 landed; P3 confirmed pre-existing
- **Worked on:** made the `ClearInspectPlayer` mock RECORD its calls in the two harnesses that drive an inspect — `detect_test.lua:80-89` (the shared `baseEnv`) and `tooltip_test.lua:700-704`. The mock is still a plain no-op to the client; it only counts. Nothing else about it changed.
- **P1 (the 0.7.9 regression itself):** `detect_test.lua:861-879` and `tooltip_test.lua:3437-3453`. Drives the real path (`INSPECT_READY` → `cacheUnitData`) and asserts (a) the inspect really ran (the data landed in the cache — the control, so a zero counter cannot mean "nothing happened") and (b) the `ClearInspectPlayer` counter did NOT move.
- **P2 (the `InspectFrame.unit` fallback):** `detect_test.lua:882-925` and `tooltip_test.lua:3455-3490`. A unit that is NEITHER `target` NOR `mouseover` — `UnitExists` says so — so the only resolution path left is `InspectFrame.unit`; the pin asserts its data is cached. `detect_test` gives it its own unit token (`guildmate`); `tooltip_test` adds a temporary `roster` unit to its `UNITS` model and removes it again.
- **P3 ALREADY EXISTED — NOT duplicated.** `tooltip_test.lua:3334` "the guild guard installs when Blizzard_InspectUI loads (modern pair)" and `:3342` "the guild guard is a NO-OP on the Classic family (no global to wrap)" (plus the swallow and the two buckets). Reported, not re-added.
- **Revert-to-fail (on a copy under `/tmp/opencode/pinproof`, never in the tree):**
  - P1 — `ClearInspectPlayer(unit)` re-added inside the `INSPECT_READY` handler → `detect_test`: `an inspect NEVER calls ClearInspectPlayer (the 0.7.9 regression) FAIL  ClearInspectPlayer calls=1` (rc=1); `tooltip_test` on CLASSIC_ERA / FOREVER / RETAIL: the same FAIL, `1/218` and `1/226` FAILED (rc=1).
  - P2 — the `insFrame.unit` arm removed from the resolver → `detect_test`: `an inspect of a unit that is neither target nor mouseover resolves through InspectFrame.unit and caches its data FAIL  cached=false` (rc=1); `tooltip_test` on the same three clients: the same FAIL (rc=1).
  - The copy was restored and re-run green after each proof.
- **Current state:** green everywhere. `Tests/harness/run_all.sh` → 71/71 on lua5.1, lua5.4 and luajit; `luacheck .` → 0 warnings / 0 errors in 88 files; `TacoTip_Extras/Tests/harness/run_all.sh` → 42/42; `Tools/verify_release.sh --worktree` → PASS; `Tools/verify_release_extras.sh --worktree` → PASS.
- **Files touched:** `Tests/harness/detect_test.lua`, `Tests/harness/tooltip_test.lua` (test files only) and this desk. NO production file was touched — `grep -rn ClearInspectPlayer --include='*.lua'` still finds zero call sites outside `Tests/harness/`.
- **Left deliberately alone:** the other five harness files that mock `ClearInspectPlayer` as a plain no-op (`batch8_pane_test`, `taint_test`, `batch4_clock_test`, `settings_test`, `load_test`, `options_test`). None of them drives an inspect (`INSPECT_READY` appears only in `detect_test.lua` and `tooltip_test.lua`), so recording there would be churn without a pin. A lane that later drives an inspect in one of them must record the call first.
- **Next step:** none — the guarantee is provable offline. The operator still owes an in-game check of the paperdoll on Retail/Forever, but the suite now stands in for it.

## 2026-10-20 — [signal:done] the 0.7.9 regression is provable offline
- **P1** the `ClearInspectPlayer` absence (counter + a control that the inspect really ran) — `detect_test.lua`, `tooltip_test.lua` on all five clients.
- **P2** the `InspectFrame.unit` fallback (a unit that is neither target nor mouseover still resolves and caches) — same two files.
- **P3** already existed in `tooltip_test.lua:3334` / `:3342` — reported, NOT duplicated.
- Both pins proved red on a copy (0.7.9 call re-added / `InspectFrame.unit` arm removed), copy restored green after each.
- Verified: 71/71 on lua5.1 / lua5.4 / luajit, `luacheck .` 0/0 in 88 files, Extras 42/42, `verify_release` PASS, `verify_release_extras` PASS.
- Files touched: `Tests/harness/detect_test.lua`, `Tests/harness/tooltip_test.lua` only. No production file.
- Signal: `desks/inspect-regression-pins/.signals/2026-10-20T23-13-08Z.json`.


