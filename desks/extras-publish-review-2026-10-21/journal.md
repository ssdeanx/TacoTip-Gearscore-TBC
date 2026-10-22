# Extras Publish Review 2026-10-21 — Journal

## 2026-10-21 — Desk opened
- **Purpose:** publish-ready READ-ONLY review of the TacoTip Extras add-on (`TacoTip_Extras/`, v1.2.3) across FIVE clients (classic_era 11509, classic_anniversary 20506, classic_titan 38002, forever 16001, live 120105).
- **Scope:** the Extras package only — Core, Scoring, Cache, RankDB, RankSync, Scanner, TacoTipAdapter, Tooltips, Frames, RankBrowser, Minimap, Options, Locale/*.lua (11), the `.toc`, and `Tests/harness/`. Questions A1–A11 of the brief.
- **Writes:** this desk (`journal.md` + `.signals/`) and ONE bench artifact `bench/audits/2026-10-21-extras-publish-review.md`. No product file, no other bench artifact, no other desk, no state-changing git, no web.
- **Next step:** read `bench/audits/2026-10-21-quit-taint-carrier.md` and `bench/audits/2026-10-20-quit-taint.md` as LEADS ONLY, then sweep the package for Blizzard-object interactions.

## 2026-10-21 — Step 1: desk opened, baselines captured
- **Worked on:** read `CAIRN.md`, `workshop.md`, `hands-up.md`; captured the pre-existing dirty-tree baseline of the workshop repo and of the mirror (`/home/sam/wow-ui-source`).
- **Current state:** the workshop repo was ALREADY dirty before this lane (many modified product files from earlier lanes). Validation bar #2 is therefore a DIFF against the captured baseline, not an empty status. Mirror baseline is `?? .vscode/ ?? SKILL.md ?? reference/`.
- **Next step:** bench-read the two prior quit-taint audits as leads.

## 2026-10-21 — Step 2: bench-read (leads only)
- **Worked on:** read `bench/audits/2026-10-21-quit-taint-carrier.md` (504 lines) and `bench/audits/2026-10-20-quit-taint.md` (460 lines) as LEADS ONLY, not as evidence.
- **Leads taken (to verify myself, per branch):**
  - L1 `2026-10-20-quit-taint.md:456` names three unaudited Extras Blizzard-frame hook sites: `TacoTip_Extras/Tooltips.lua:1589-1693`, `TacoTip_Extras/Frames.lua:1335-1398`, `TacoTip_Extras/Options.lua:628-633`.
  - L2 the shared `GameTooltip` script matrix (classic declares `OnTooltipSetUnit`/`OnTooltipSetItem`/`OnTooltipSetSpell`; live/forever do not; `OnShow` live/forever only; `OnHide` all five; `OnTooltipCleared` live/forever only) — MUST be re-verified per branch, not inherited.
  - L3 `GameTooltipStatusBar` IS a live global on all five branches (XML `$parentStatusBar` inside `GameTooltipTemplate` / `GameTooltip`) — a grep is not a proof of absence.
  - L4 `hooksecurefunc` cannot hook a SCRIPT (only a method) — `HookScript` is the script-chain mechanism.
  - L5 `InspectGuildFrame_Update` global replacement exists on forever/live only.
  - L6 a containment wrapper that swallows a raise swallows the evidence: the `pcall` must be INSIDE the containment.
  - L7 Lua 5.1: `...` outside a vararg function is a COMPILE ERROR — the exact shape that took `Tooltips.lua` down on 2026-10-21 (`2026-10-21-quit-taint-carrier.md` §10.2).
- **Current state:** no product file touched. Leads recorded, none yet accepted as evidence.
- **Next step:** sweep `TacoTip_Extras/` for every Blizzard-object interaction (A1).

## 2026-10-21 — Step 3: A1/A11 sweep of the package
- **Worked on:** enumerated every Blizzard-object interaction in `TacoTip_Extras/` (no `Detours`, no `Mixin(`, no `rawset` on a Blizzard global; 3 `hooksecurefunc` sites; 12 `HookScript` sites; 2 `rawset(_G, ...)` families on NEW globals only).
- **Containment boundary read:** `Core.lua:38-60` (`secureCallFn` probe + `Core.RunUntainted`), `Frames.lua:70-94` (`boundedCallback`), `Tooltips.lua:1653-1673` (`contained`).
- **Current state:** three containment gaps found and recorded; no product file touched.
- **Next step:** per-branch mirror verification (A2–A6).

## 2026-10-21 — Step 4: per-branch mirror verification (A2, A3, A4, A5, A6)
- **Worked on:** five branches read through `git -C /home/sam/wow-ui-source show origin/<branch>:<path>`; XML probed with a namespace-aware parser so the `<Scripts>` blocks are real.
- **Settled per branch:**
  - `InspectFrame_Show` / `InspectFrame_UnitChanged` / `InspectSwitchTabs` are LUA globals on all five.
  - `InspectFrame_UnitChanged` has **NO call site anywhere in the tree on any branch** (whole-tree sweep) → the Extras' post-hook on it is DEAD on all five.
  - `InspectSwitchTabs` IS called from a frame's script chain (`InspectFrameTab_OnClick` = the tab Button's `<OnClick>`) on all five.
  - `InspectFrame` carries `hidden="true"` on all five → its `OnShow` fires.
  - `PaperDollFrame` / `InspectPaperDollFrame` carry **NO** `hidden` attribute on any branch → shown from creation → their `OnShow` has already fired.
  - shared `GameTooltip`: classic declares `OnTooltipSetUnit`/`OnTooltipSetItem`/`OnTooltipSetSpell`/`OnHide`/`OnUpdate`; mainline declares `OnShow`/`OnUpdate`/`OnHide`/`OnTooltipCleared`/`OnEvent`/`OnLoad`/`OnTooltipSetDefaultAnchor` and **no** `OnTooltipSetUnit`/`OnTooltipSetItem`.
  - `GameTooltip_OnTooltipSetUnit` / `GameTooltip_OnTooltipSetItem` are **absent from the whole `Interface/` tree on forever and live** and present on the classic family.
  - there is **no `MinimapButton` frame and no `MinimapButton` template on any branch**.
  - `InterfaceOptions_AddCategory` and `InterfaceOptionsFrame_OpenToCategory` are **absent from the whole tree AND the generated API docs on all five**; `Settings.RegisterCanvasLayoutCategory` / `RegisterCanvasLayoutSubcategory` / `RegisterAddOnCategory` / `OpenToCategory` are **present on all five**.
- **Current state:** the per-branch tables are settled; the driver mode is the same under either reading of `HasScript` because `pcall(tooltip.HookScript, ...)` is the effective gate.
- **Next step:** A7–A10 (saved variables, whisper, locale parity, packaging) and the validation bar.

## 2026-10-21 — Step 5: A7–A10 + validation bar
- **Worked on:** `Core.lua:493-540` (database init), whole-package whisper sweep, locale key/value diff across all 11 files, `Tools/verify_release_extras.sh --worktree`.
- **Results:** schema 2, first-install shape written by `normalizeSettings`; no `SendChatMessage` / whisper transport anywhere (only `C_ChatInfo.SendAddonMessage` and `CHAT_MSG_ADDON`); all 11 locales publish the SAME 154 keys (no missing, no extra, no duplicate, no empty) but zhTW and enUS differ in key ORDER; the extras package verifier PASSES (29 files, 23 TOC-listed runtime files, icon present, no PNG/Tests).
- **Suites:** `bash TacoTip_Extras/Tests/harness/run_all.sh` → 42/42 PASS on all three interpreters; `luacheck TacoTip_Extras` → 0 warnings / 0 errors in 26 files.
- **Current state:** all eleven questions answered; artifact being written.
- **Next step:** write `bench/audits/2026-10-21-extras-publish-review.md`, then the `done` signal.

## 2026-10-21 — Step 6: artifact written, validation bar met
- **Worked on:** wrote `bench/audits/2026-10-21-extras-publish-review.md` (1292 lines) answering A1–A11 per branch; ran the four validation-bar checks.
- **Validation bar:**
  1. `git -C /home/sam/wow-ui-source status --porcelain` — **UNCHANGED** (byte-identical to the pre-work baseline: `?? .vscode/`, `?? SKILL.md`, `?? reference/`). Every mirror read was `git show` / `git grep` / `git ls-tree`.
  2. `git -C /home/sam/TacoTip-Gearscore-TBC status --short` — diffed against the pre-work baseline. **FOUR** new untracked entries: two MINE (`desks/extras-publish-review-2026-10-21/`, `bench/audits/2026-10-21-extras-publish-review.md`) and two from CONCURRENT lanes that were running while this one worked (`bench/audits/2026-10-21-publish-gate-verification.md` — desk `quit-taint-fix`; `desks/main-publish-sweep-2026-10-21/`). **ZERO** product-file changes.
  3. Every `path:line` in the artifact came from a command run in this lane, with the output quoted inline for the load-bearing client claims.
  4. Every client claim names its branch and carries VERIFIED / ASSUMED / UNKNOWN.
- **Suites run in this lane:** `bash TacoTip_Extras/Tests/harness/run_all.sh` → 42/42 PASS (lua 5.1 / lua 5.4 / luajit); `luacheck TacoTip_Extras` → 0 warnings / 0 errors in 26 files; `bash Tools/verify_release_extras.sh --worktree` → PASS.
- **Findings:** 0 blocking confirmed; 4 should-fix (F1, F2, F3, F12-verify) + 7 nit (F4, F5, F6, F7, F8, F9, F10).
- **Current state:** artifact on the bench; the ONE thing the mirror cannot settle is whether `Frame:HookScript` validates against the frame's XML `<Scripts>` declarations or against the frame TYPE's script set. Two pieces of evidence conflict (§12 of the artifact). It is escalated with a one-line in-game probe: `/dump PaperDollFrame:HasScript("OnSizeChanged")`. It is reported as UNKNOWN and **not** as a defect, per `CAIRN.md`.
- **Next step:** the operator runs the two `/dump` probes; the result decides whether `Frames.lua:1356` / `Frames.lua:1405` need the `HasScript` guard `Options.lua:626-635` already uses.

## 2026-10-21 — [signal:done] Extras publish review landed
- **run_id:** `extraspublishreview20261021`
- **artifact:** `bench/audits/2026-10-21-extras-publish-review.md`
- **signal:** `desks/extras-publish-review-2026-10-21/.signals/2026-10-21T14:32:33Z.json` (`signal_type: execution`, `subtype: done`)
- **result:** 0 blocking confirmed; 4 should-fix (F1, F2, F3, F12-verify); 7 nit. Suites green (42/42), luacheck 0/0, `verify_release_extras --worktree` PASS.
- **escalated in the signal:** `/dump PaperDollFrame:HasScript("OnSizeChanged")` — the one question the FrameXML mirror cannot answer.
