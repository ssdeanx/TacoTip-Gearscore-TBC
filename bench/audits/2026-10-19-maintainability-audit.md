# Maintainability / code-smell audit — MAIN + Extras (2026-10-19)

**Placement note:** reviewing session had no file-write or shell tools; this report is filed by the orchestrator from the reviewing agent's inline handoff (desk `maintainability-audit`, agent `janitor-audit`, run_id `janitor1`). The reviewing session could NOT read `/home/sam/wow-ui-source` (external-directory permission guard, no shell), so its mirror claims were marked `[MIRROR-UNVERIFIED]` — **the orchestrator re-verified the client-fact claims below against the mirror with `git show` / `git grep` on all five branches** and marks each as VERIFIED.

**Counts reported:** 6 HIGH, 17 MEDIUM, 18 LOW, 0 CRITICAL. No behaviour change was required for any finding below.

## Orchestrator-verified client facts (all five branches)

| Claim | Verification | Verdict |
|---|---|---|
| `INVTYPE_HANDS` (gear-panel hands label, `TacoTip_Extras/RankBrowser.lua:1070`) | `git grep INVTYPE_HANDS` over origin/classic_era, classic_anniversary, classic_titan, forever, live → **0 hits on every branch**. `INVTYPE_HAND` → present on all five. The other 15 slot globals (HEAD/NECK/SHOULDER/CLOAK/CHEST/WRIST/WAIST/LEGS/FEET/FINGER/TRINKET/WEAPONMAINHAND/WEAPONOFFHAND/RANGED) → present on all five. `INVTYPE_BACK`/`INVTYPE_FINGER1`/`INVTYPE_FINGER2` → absent on every branch. | **CONFIRMED DEFECT.** The Hands label always fell back to the English literal in every client and language, contradicting `RankBrowser.lua:1058-1062` and `README.md:104`. Fix in Batch 7. |
| StaticPopup pool size (`main.lua:4193-4196`, bound = 4) | `name="StaticPopup1..4"` present in `Blizzard_StaticPopup_Game/GameDialog.xml` on **all five branches**, no fifth frame | **VERIFIED.** The constant is correct; the comment lacked branch qualification (Batch 7). |
| GameMenu / Settings strata (`TacoTip_Extras/RankBrowser.lua:36-51`) | `GameMenuFrame` = `toplevel="true" frameStrata="DIALOG"`; `SettingsPanel` = `toplevel="true" frameStrata="HIGH"` — **identical on all five branches** | **VERIFIED.** The `FULLSCREEN_DIALOG` + top-level browser choice is correct on every client (Batch 7 qualifies the citation). |
| Bare `GetItemInfoInstant` global | `Blizzard_DeprecatedItemScript/Deprecated_ItemScript.lua:10` aliases it to `C_Item.GetItemInfoInstant` on classic_era/anniversary/titanforge; **the file is absent on origin/forever and origin/live** | **CONFIRMED DEFECT** — see the proctor report, `main.lua:2736`. |
| `Settings.RegisterCanvasLayoutCategory` arity | `Blizzard_Settings_Shared/Blizzard_Settings.lua:161/:165/:133` — plain functions on a namespace table, called with a dot | Confirmed; the `options_test.lua` mock is wrong (proctor M2). |

## Confirmed defects fixed in Batch 7

- **S25 (MEDIUM→HIGH, user-visible):** `INVTYPE_HANDS` → `INVTYPE_HAND`; the 17 client slot globals are now pinned in the harness so a typo cannot ship silently again.
- **S10 (MEDIUM, raised):** the bare `GetServerTime` read in `RankBrowser.lua` was a recorded, knowingly-unfixed luacheck warning. Resolved by the orchestrator's repo-wide lint repair (root `.luacheckrc` now declares `GetServerTime`; `luacheck .` = 0/0 across 85 files).

## Fixed by the orchestrator before Batch 7 (config drift)

- **S5/S28:** the root `.luacheckrc` harness override pointed at `TacoTip_Forever/Tests/harness/*.lua`, a directory that no longer exists — so `luacheck .` from the repo root checked the real harness and the whole Extras add-on with **no** overrides (182 warnings, no effective coverage of those files). Root config now carries the live harness path, the Extras-only Blizzard globals, the locale line-length waiver, and the vendored LibDBIcon names. `luacheck .` → **0 warnings / 0 errors in 85 files**; `cd TacoTip_Extras && luacheck .` → **0/0 in 26 files**.
- **S27:** `TacoTip_Extras/.luacheckrc` declared `SLASH_TTGSEDEBUG1` / `SLASH_TTGSE1` — both dead; the live names are `SLASH_TTEXTRASDEBUG1` / `SLASH_TTEXTRAS1` (`Core.lua:700`, `Options.lua:1493`). The "Reported, NOT fixed" note described a defect that was fixed. Now corrected.
- **S29:** `_TacoTipPawnReady` existed in no source file outside the stale `OLD/` copy; removed from `.luacheckrc`, `.luarc.json`, `.vscode/settings.json`, and re-declared **scoped to `OLD/*.lua`** so that copy still lints clean.
- **S28 (locale waiver):** root config now applies `max_line_length = false` to `Locale/*.lua`, mirroring the Extras config (a translated help paragraph is 1000+ columns in Russian by design).

## Open findings carried (not publish blockers)

- **S1 (HIGH):** `main.lua:139` / `:152` compare the raw Pawn version globals with `>=` — a string-typed version raises **at file scope** and aborts addon load. `pawn.lua`/`options.lua` were fixed with `tonumber` guards; `main.lua` was not, and the CHANGELOG claim "no longer raises on any probe" was false. → Batch 7 item 2.
- **S2 (HIGH):** `main.lua` calls the raw `C_Item.RequestLoadItemDataByID`, bypassing the shared 2 s throttle (`TT_GS.RequestLoadItemDataByID`, gearscore.lua:107-144). → Batch 7 item 4.
- **S3 (HIGH):** `onTooltipSetUnit` is 806 lines with 11 responsibilities — structural, deferred.
- **S4 (HIGH):** the harness `check()` helper has **inverted argument order between the two suites** (MAIN `check(name, cond, detail)` vs Extras `check(cond, label, detail)`); the same call shape is interpreted oppositely, so a MAIN-style call copied into Extras passes silently. → Batch 7 item 3 (loud trap detection, no call-site churn).
- **S6 (HIGH):** ~20 stale CHANGELOG anchors + 2 substantively false claims — partially resolved by Batch 7 (the Pawn-probe claim); the anchor sweep remains.
- **S7, S8, S9, S11–S24 (MEDIUM):** `REQUIRED_SLOTS` duplicated in 6 places; `isFiniteNumber` ×4; class-colour resolution ×4 with three fallback greys; `setFresh`/`setMigratedEquipmentDisplayDefaults` byte-identical; two `safeCall` wrappers with different semantics; `TT.ev` as 24 free-form counters; two locale engines; dual `show_server_rank`/`showServerRank` key; dead `TT`/`Scoring` exports; bracket table ×3; two session clocks; `LibForeverInspector` at 5648 lines. Structural — deferred by design.
- **D12 (decision) — RESOLVED BY THE OPERATOR: keep the client's own `INVTYPE_*` strings.** "Get the label from wherever you can": the client's translated `INVTYPE_*` globals first (that is the feature — the panel is localized in languages the add-on has never been translated into), with the addon's English fallback when a global is absent. Batch 7 fixes the one bad name and pins all 17 so a typo cannot ship silently again.
- **D13 (decision):** require branch-qualified (`origin/<branch>:<path>`) citations for any "exactly N" / "all clients" claim; unqualified citations are not evidence.
- **M7 / L-NEW1 (open):** ruRU MONK/DEMONHUNTER/EVOKER spec names are still German/English placeholders (`LibForeverInspector.lua:345-347`). **Needs a translator — no Russian strings were invented.**
