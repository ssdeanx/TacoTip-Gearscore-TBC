# Main Publish Sweep 2026-10-21 — Journal

## 2026-10-21 — Desk opened
- **Purpose:** READ-ONLY publish-ready sweep of the MAIN add-on (`main.lua`,
  `options.lua`, `gearscore.lua`, `pawn.lua`, `textures.lua`, `Locale/*.lua`,
  `TacoTip.toc`, `Libs/`) before a release that ships to ~120k downloads.
  Five clients: classic_era (11509), classic_anniversary (20506),
  classic_titan (38002), forever (16001), live (120105).
- **Scope:** B1 invariants, B2 HookScript/SetScript on Blizzard frames,
  B3 the securecall containment, B4 `CanInspect` arity, B5 locale parity,
  B6 `.toc` + package, B7 client APIs not in the mirror's generated docs.
  Report defects only — NO patches, NO product-file edits.
- **Writes allowed:** this desk (`journal.md`, `.signals/`) and exactly one
  bench artifact `bench/audits/2026-10-21-main-publish-sweep.md`.
- **Context:** a fix landed today for the Classic Era exit-game refusal —
  (a) the vendored library no longer replaces the client's global `PlaySound`
  and the refusal's sound interception moved to `GetGameMessageInfo`;
  (b) every addon callback entering a Blizzard frame's script chain is
  wrapped in `securecall` (`main.lua`'s `runUntainted`, `options.lua`'s copy);
  (c) a load-time probe only arms the containment if `securecall` actually
  runs a function. Lead reading: `bench/audits/2026-10-21-quit-taint-carrier.md`.
- **Next step:** read the two prior audits as LEADS only, then sweep B1..B7
  against the mirror branch by branch.

## 2026-10-21 — Step 1: bench-read (prior audits as LEADS only)
- **Worked on:** read `bench/audits/2026-10-21-quit-taint-carrier.md` (504 lines) and
  `bench/audits/2026-10-20-inspect-and-guild-line-history.md` (77 lines).
- **What I took as a lead, not as fact:** (a) the carrier was the vendored library
  replacing the client's global `PlaySound`; (b) `securecall` is the containment
  primitive and a `hooksecurefunc` post-hook body is NOT a taint boundary;
  (c) the client's own `CanInspect(unit, true)` is the two-argument shape the
  add-on must not use; (d) the `$parentX` -> global `FX` rule; (e) the inspect-frame
  guild guard and the guild/level line-ownership proof are load-bearing.
- **What I re-checked rather than believed:** every one of those claims was re-derived
  from the mirror in this lane (see the bench artifact). The prior audit's own
  corrections (the `GameTooltipStatusBar` absence claim it withdrew) are recorded as
  leads, not as evidence.
- **Current state:** desk open, nothing written outside it, mirror untouched.
- **Next step:** B1 invariants, B2 hook sites, B3 containment, B4 CanInspect arity,
  B5 locale parity, B6 toc/package, B7 client-API surface.

## 2026-10-21 — Step 2: B2 — every HookScript/SetScript on a Blizzard frame
- **Worked on:** enumerated every `HookScript` (8 in `main.lua`, 0 in `options.lua`)
  and every `SetScript` on a Blizzard frame, then checked each target's XML
  declaration on all five branches.
- **Key method result (VERIFIED):** `OnShow` and `OnHide` are engine-default frame
  scripts — `HookScript` on them does NOT raise even when the frame declares no
  `<Scripts>` block. Two pieces of Blizzard's own shipped code prove it:
  `origin/classic_era:Interface/AddOns/Blizzard_UIPanels_Game/Classic/SkillFrame.xml:129`
  declares no `<Scripts>` at its own level, yet
  `origin/classic_era:Interface/AddOns/Blizzard_PTRFeedback/Blizzard_PTRFeedback_Tooltips.lua:152`
  does `SkillFrame:HookScript("OnShow", UpdateSkillTooltips)`; and
  `origin/live:Interface/AddOns/Blizzard_PTRFeedback/Blizzard_PTRFeedback.lua:1`
  creates `PTR_IssueReporter = CreateFrame("Frame", nil, ...)` with no template and no
  prior `SetScript`, yet
  `origin/live:Interface/AddOns/Blizzard_PTRFeedback/Blizzard_PTRFeedback_Frames.lua:773`
  does `PTR_IssueReporter:HookScript("OnHide", function() surveyFrame:Hide() end)`.
- **Result:** no unguarded `HookScript` on a tooltip-specific script. The three
  tooltip-specific hooks all sit behind `HasScript` (`main.lua:3020-3021`, `:3414`,
  `:3427`, `:3432`).
- **Current state:** B2 answered per branch; one nit recorded (`main.lua:4201`).
- **Next step:** B3 containment, then B1/B4/B5/B6/B7.

## 2026-10-21 — Step 3: B3 — the containment, second pair of eyes
- **Worked on:** every `runUntainted` / `secureCallFn` / `safeCall` use in `main.lua`
  and `options.lua`, and the probe in each file.
- **Verified clean:** argument forwarding (`runUntainted` is `local function
  runUntainted(fn, ...)`, `main.lua:517`; `options.lua:39`), the load-time probe
  (`main.lua:510-514`, `options.lua:32-36`), `securecall` argument forwarding
  (Blizzard's own three-argument call on all five branches), and NO `...` inside a
  non-vararg inner function anywhere (the Lua 5.1 compile-error shape from the
  prior audit does not occur in the main add-on).
- **Defect class found:** two containment payloads are not fully self-contained —
  `main.lua:3418` and `main.lua:3434` call `isUnitFramePeriodicUpdate(tFrame)` and
  `cancelDelayedTooltip(tFrame)` outside any `pcall`/`safeCall`, so `securecall`
  would swallow a raise there silently, while the no-`securecall` fallback path
  (`main.lua:524`) propagates it. The comment at `main.lua:521-523` overstates the
  guarantee for these two sites.
- **Current state:** B3 answered; one should-fix recorded.
- **Next step:** B1 invariant verdicts, B4 arity, B5 locale parity, B6 package, B7 APIs.

## 2026-10-21 — Step 4: B1/B4/B5/B6/B7 — the rest of the sweep
- **B1 (invariants):** all eight verified against the tree and against `git diff HEAD`.
  No formula drift: the `SlotMOD` table is md5-identical to HEAD and the
  numeric-literal multiset of `gearscore.lua` differs only by `BRACKET_SIZE = 1000`
  (the explicit Unknown default) and two literals in a new error counter.
- **B4 (CanInspect):** the ONLY call to the client's global in the shipped tree is
  `Libs/LibForeverInspector/LibForeverInspector.lua:5073` —
  `local ok, allowed = pcall(api, unit)` — ONE argument. `main.lua`, `options.lua`,
  `gearscore.lua`, `pawn.lua`, `textures.lua` never mention `CanInspect`.
- **B5 (locale parity):** same 239-key set in all 11 files, no empty values, no
  key present in only one locale. ORDER DIFFERS in all ten non-English files.
- **B6 (toc/package):** every toc-listed file exists; `Tools/verify_release.sh
  --worktree` PASSes with 27 files; two UNTRACKED vendored libraries sit in `Libs/`
  and would ship in a directory-zipped package.
- **B7 (client APIs):** every Blizzard global the tree calls is present in the
  client's whole `Interface/` tree on all five branches, and every one that is
  branch-dependent is guarded. IMPORTANT METHOD RESULT: the classic branches'
  generated API docs are a smaller set that does NOT document `CreateFrame`,
  `UnitRace`, `UnitIsDeadOrGhost`, `GetBuildInfo`, `IsShiftKeyDown` or
  `C_Item.GetItemLinkByGUID` — all of which exist on Classic Era — so "absent from
  the generated API docs" is NOT an absence signal on the classic branches.
- **Current state:** B1-B7 answered; tree verified green (harness 71/71, luacheck
  0 warnings / 0 errors, `verify_release.sh --worktree` PASS).
- **Next step:** write the bench artifact, then the `done` signal.

## 2026-10-21 — Step 5: validation bar
- **Worked on:** re-ran the four validation-bar checks.
- **1. mirror unchanged:** `git -C /home/sam/wow-ui-source status --porcelain` returns
  the same three entries as the baseline captured before any work (`?? .vscode/`,
  `?? SKILL.md`, `?? reference/`). VERIFIED.
- **2. repo:** `git status --short` shows NO change to any product file. The only
  additions are `desks/main-publish-sweep-2026-10-21/` (this desk) and
  `bench/audits/2026-10-21-main-publish-sweep.md` (one bench artifact). The
  pre-existing modifications to `main.lua`, `options.lua`, `gearscore.lua`,
  `pawn.lua`, `Locale/*`, `TacoTip.toc`, `Libs/*` were present BEFORE this lane
  (baseline captured at `/tmp/opencode/tacotip-status-baseline.txt`) and are
  unchanged by it. VERIFIED.
- **3. provenance:** every `path:line` cited in the bench artifact came from a
  command run in this lane. VERIFIED.
- **4. evidence labels:** every client claim in the artifact names its branch and
  carries VERIFIED / ASSUMED / UNKNOWN. VERIFIED.
- **Tree state at hand-off:** `bash Tests/harness/run_all.sh` -> 71/71 passed;
  `luacheck .` -> 0 warnings / 0 errors in 88 files;
  `bash Tools/verify_release.sh --worktree` -> PASS (27 files).
- **Next step:** emit the `done` signal.

## 2026-10-21 — [signal:done] main add-on publish sweep landed
- **Artifact:** `bench/audits/2026-10-21-main-publish-sweep.md` (B1-B7, per branch).
- **Signal:** `desks/main-publish-sweep-2026-10-21/.signals/2026-10-21T14:43:55Z.json`,
  `signal_type: "execution"`, `subtype: "done"`, `run_id: "mainpublishsweep20261021"`.
- **Headline:** 0 blocking, 1 should-fix, 7 nits. All eight invariants HOLD. No
  `HookScript`/`SetScript` site can raise on any of the five clients. `CanInspect`
  is called with exactly one argument, and the only call site is one line long.
- **The should-fix:** `main.lua:3418` and `main.lua:3434` — two containment
  payloads are not fully self-contained, so `securecall` would swallow a raise
  there silently while the fallback path would propagate it.
- **The method result worth carrying forward:** the classic branches' generated API
  docs are an incomplete set (`CreateFrame`, `UnitRace`, `UnitIsDeadOrGhost`,
  `GetBuildInfo`, `IsShiftKeyDown`, `C_Item.GetItemLinkByGUID` are all absent from
  them and all present in the client's own tree). On classic, "absent from the
  generated API docs" must never be reported as an absence.
- **Nothing was edited.** The mirror is untouched; the repo shows only this desk
  and the one bench artifact added.

## 2026-10-21 — validation bar, re-checked after the signal
- **Product files untouched:** every shipped file's mtime predates this lane
  (`main.lua` 09:21:31, `options.lua` 09:09:58, `gearscore.lua` 17:01:50 the
  previous day, `pawn.lua` 19:12:15 the previous day, `textures.lua` 08:04:30 the
  previous day, `TacoTip.toc` 13:31:55 the previous day,
  `Libs/LibForeverInspector/LibForeverInspector.lua` 08:55:36). The lane opened at
  ~10:15 and wrote only to its own desk and its one bench artifact.
- **Two bench artifacts that are NOT mine** appeared during the lane, from concurrent
  desks: `bench/audits/2026-10-21-extras-publish-review.md` (desk
  `extras-publish-review-2026-10-21`, 10:32:19) and
  `bench/audits/2026-10-21-publish-gate-verification.md` (desk `quit-taint-fix`,
  10:24:22). Neither is a product file; recorded so the next reader does not
  attribute them to this lane.
- **Mirror:** identical to the baseline taken before the first command here.
