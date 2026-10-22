# taint-client-source-2026-10-21 — Journal

## 2026-10-21 — Desk opened
- **Purpose:** verify, against the Blizzard client source mirror
  (`/home/sam/wow-ui-source`, `origin/`-qualified), the exact coupling between
  the WoW game menu (Exit / Logout) and the shared `GameTooltip`, across all
  five supported client families: `classic_era`, `classic_anniversary`,
  `classic_titan`, `forever`, `live`.
- **Scope:** READ-ONLY client-truth analysis. Writes are limited to this desk
  (`journal.md`, `.signals/`) and one bench artifact
  `bench/audits/2026-10-21-gamemenu-tooltip-coupling.md`. No product file is
  touched; no product change is proposed; no web.
- **Questions:** Q1 menu-button tooltip path, Q2 which tooltip
  `GetAppropriateTooltip` returns, Q3 the restricted call and the
  `Logout`/`Quit` identity, Q4 whether Blizzard itself puts code in the shared
  tooltip's script chain, Q5 the classic-family unit path, Q6 whether a secure
  dispatch exists for the classic tooltip, Q7 the mover/anchor path.
- **Context:** the prior audit `bench/audits/2026-10-20-quit-taint.md` (desk
  `quit-taint`) is **leads only** — this desk re-derives every claim from the
  mirror and labels each VERIFIED / ASSUMED / UNKNOWN per `CAIRN.md`.
- **Next step:** run the Q1–Q7 sweeps on all five branches, quote
  `path:line` for every answer, write the bench artifact, emit one `done`
  signal.
- **Mirror state at open (pre-existing, not mine):** `git -C
  /home/sam/wow-ui-source status --porcelain` -> `?? .vscode/`, `?? SKILL.md`,
  `?? reference/` (untracked, present before this desk touched anything).
  Mirror `HEAD` = `8165d4cd6` (branch `classic_era`). Snapshot kept at
  `/tmp/opencode/mirror-status-before.txt`.
  **Correction (2026-10-21, end of session):** this line originally read
  "`HEAD` = `0395d99`" — that was a mis-read: `0395d99` is the **TacoTip
  repo's** HEAD, because the `git rev-parse` ran with the TacoTip working
  directory in effect. The mirror's HEAD is `8165d4cd6` and the mirror's
  reflog shows its last state-changing git operation was a
  `checkout: moving from classic_anniversary to classic_era` at
  **2026-10-14 10:51:26 -0400**, a week before this session. So the mirror
  was not touched.
- **Repo state at open (pre-existing, not mine):** the TacoTip tree is
  intentionally uncommitted (`AGENTS.md`: "no state-changing git"). Snapshot of
  `git status --short` kept at `/tmp/opencode/tacotip-status-before.txt`; my
  lane must add **only** `desks/taint-client-source-2026-10-21/` and
  `bench/audits/2026-10-21-gamemenu-tooltip-coupling.md` to that list.

## 2026-10-21 — Q1–Q4 swept on all five branches
- **Worked on:** read the full `MainMenuFrameTemplates.lua`, `GameMenuFrame.lua`,
  `GameTooltip.xml`, `GameTooltipTemplate.xml` on all five branches; located every
  `GetAppropriateTooltip` definition; read `RestrictedActionsDocumentation.lua`;
  swept the whole tree for `HookScript`/`SetScript`/`hooksecurefunc` on tooltips.
- **Current state (findings so far, all VERIFIED by `git show`/`git grep`):**
  - **Q1** the menu-button tooltip path is **byte-identical logic on all five
    branches**; only the line offsets differ (classic family `:38-48`,
    live/forever `:46-56`). The handlers are installed **only when the button is
    disabled** (`if isDisabled and disabledText`, `MainMenuFrameTemplates.lua:37`).
    Call order: `GetAppropriateTooltip()` → `SetOwner(newButton,"ANCHOR_RIGHT")`
    → `SetText(text)` → `GameTooltip_AddErrorLine(tooltip, disabledText)` →
    `Show()`; OnLeave → `GetAppropriateTooltip():Hide()`.
    **No** `ClearLines`/`SetPoint`/`EnableMouse`/`FadeOut`/`SetPadding` in the menu path.
  - **Q2** the classic family has **TWO** global `GetAppropriateTooltip`
    definitions (`Blizzard_SharedXMLBase/FrameUtil.lua:277-279` **and**
    `Blizzard_SharedXML/Classic/SharedUIPanelTemplates.lua:759` era / `:729` titan).
    Bodies are identical (`return UIParent and GameTooltip or GlueTooltip;`).
    The prior audit cited only the first.
  - **Q3** `Logout`/`Quit` have **no Lua definition** in any of the five trees
    (whole-tree sweep) **and they ARE in the generated API docs** as
    `Type = "Function"` in the `ConnectionScript` namespace
    (`Blizzard_APIDocumentationGenerated/ConnectionDocumentation.lua:86-93`).
    → they are engine functions **with names**; the reporter's `'UNKNOWN()'` is
    a reporter-side rendering, not evidence of an anonymous function.
  - **Q4** the only Blizzard code that hooks the shared `GameTooltip`'s script
    chain is `Blizzard_PTRFeedback` — and its `.toc` carries
    `## OnlyBetaAndPTR: 1` on **all five branches**, so it is **not loaded on a
    release build**. Whole-tree `HookScript` census: 18 sites on classic_era,
    40 forever, 29 live.
- **Next step:** Q5 (classic `GameTooltipMixin:SetUnit`), Q6 (secure dispatch),
  Q7 (`GameTooltip_SetDefaultAnchor`), then write the bench artifact.

## 2026-10-21 — Q5–Q7 swept; bench artifact written
- **Worked on:** the classic `GameTooltipMixin` (5 methods, no `SetUnit`);
  `GameTooltip_OnTooltipSetUnit/Item/Spell` (classic `GameTooltip.lua:498-530`);
  `TooltipDataHandler.lua` on the classic branches and the
  `Blizzard_SharedXMLGame.toc` load filters; `forceinsecure`; the
  `GameTooltip_SetDefaultAnchor` definitions and every call site.
- **Current state — the findings that matter:**
  - **Q5** the question's premise is **false for the classic family**:
    `GameTooltipMixin:SetUnit` does not exist on any classic branch. The
    classic `GameTooltipMixin` (`Blizzard_SharedXML/Classic/GameTooltipTemplate.lua:1-23`)
    has exactly five methods. `GameTooltip:SetUnit(...)` is an **engine
    method** — called unguarded at `Blizzard_UnitFrame/Classic/UnitFrame.lua:453`.
    The `OnTooltipSetUnit` handler is
    `GameTooltip_OnTooltipSetUnit(self)` (`Blizzard_GameTooltip/Classic/GameTooltip.lua:498-503`):
    the addon callback is called with **the tooltip frame only** (no unit
    token), and the call is **plain insecure code** — no `securecall`,
    no `securecallfunction`, no `forceinsecure` on that path.
  - **Q6** the secure attribute-delegate machinery (`AddCall`,
    `AttributeDelegate`, `forceinsecure`) **is present verbatim in the
    classic tree** (`Blizzard_SharedXMLGame/Tooltip/TooltipDataHandler.lua:181-209`,
    `:111-125`) — but on `classic_era` the file is
    **`[ExcludeLoadGameType vanilla]`** (`Blizzard_SharedXMLGame.toc:9`), so
    the global `TooltipDataProcessor` does not exist there at all. On
    `classic_anniversary` (cata) and `classic_titan` (mists) the file
    **does** load, but the classic shared `GameTooltip` mixes in only the
    5-method `GameTooltipMixin`, so the dispatch is **present but not wired**.
    `forever`/`live`: wired via `mixin="GameTooltipDataMixin"`
    (`Mainline/GameTooltip.xml:4`, `Mainline/GameTooltip.lua:951` / `:960`).
    → **no secure dispatch for the shared tooltip on any classic branch.**
  - **Q4** the only Blizzard code hooking the shared `GameTooltip`'s script
    chain is `Blizzard_PTRFeedback`, whose `.toc` is
    `## OnlyBetaAndPTR: 1` on **all five** branches → not on a release
    build. The `forever` `hooksecurefunc(GameTooltip, …)` sites are method
    hooks, not script-chain hooks. `Blizzard_GamepadActionBars`'s
    `self:GetTooltip()` returns a dedicated `ActionTooltip`, not the shared one.
  - **Q7** **the game menu never reaches `GameTooltip_SetDefaultAnchor`.**
    The menu anchors with `SetOwner(newButton, "ANCHOR_RIGHT")`. The
    anchor helper is called by unit frames, item frames, action buttons and
    various UI frames — **no hit under `Blizzard_GameMenu/` on any branch.**
    The classic family has **two** `GameTooltip_SetDefaultAnchor`
    definitions with different bodies.
- **Corrections to the prior audit** (full text in the artifact §10): the
  `'UNKNOWN()'` inference; the missed second `GetAppropriateTooltip`
  definition; the fact that the classic `TooltipDataHandler.lua` is not
  even loaded on `classic_era`; and the new fact that `forever`/`live`
  declare **no** `OnTooltipSet*` scripts anywhere in the tree.
- **Artifact:** `bench/audits/2026-10-21-gamemenu-tooltip-coupling.md`
  (1294 lines).
- **Next step:** none — this lane is finished. The artifact is client truth
  only; it proposes no product change. The taint hop itself remains
  ASSUMED and is listed in the artifact's "what I could not establish".

## 2026-10-21 — [signal:done] gamemenu↔tooltip coupling verified on five branches
- Artifact: `bench/audits/2026-10-21-gamemenu-tooltip-coupling.md`
  (run_id `taintclientsrc`). Q1–Q7 answered per branch with `path:line`
  quotes. Six corrections to standing knowledge. No product file touched.
