# Quit Taint — Journal

## 2026-10-20 — Desk opened
- **Purpose:** prove from the client source (FrameXML mirror, `origin/`-qualified) why logging out is blocked on Classic Era (`[ADDON_ACTION_FORBIDDEN] AddOn 'TacoTip' tried to call the protected function 'UNKNOWN()'` from `Blizzard_GameMenu/Shared/GameMenuFrame.lua:69`), and name the minimal fix that works on all five clients (classic_era, classic_anniversary, classic_titan, forever, live).
- **Scope:** read-only client analysis + read-only read of our tree (`main.lua`, `options.lua`, `Libs/`). **No product file may be edited.** The only writes are this desk, its `.signals/`, and one bench artifact under `bench/audits/`.
- **Method:** `git -C /home/sam/wow-ui-source show origin/<branch>:<path>`. Every claim labelled VERIFIED / ASSUMED / UNKNOWN per `CAIRN.md`.
- **Next step:** read `Blizzard_GameMenu/Shared/GameMenuFrame.lua` on all five branches; locate GameTooltip's template/creation site on `forever` and `live`; then enumerate every taint-capable operation in our tree.

## 2026-10-20 — Step 1: orientation done
- Read `CAIRN.md`, `workshop.md`, `hands-up.md`, `bench/audits/2026-10-20-session-retrospective.md`, `bench/audits/2026-10-20-inspect-and-guild-line-history.md`.
- Branches confirmed present in the mirror: `origin/classic_era`, `origin/classic_anniversary`, `origin/classic_titan`, `origin/forever`, `origin/live`.
- `Blizzard_GameMenu/Shared/GameMenuFrame.lua` exists on all five branches (VERIFIED by `git ls-tree`).

## 2026-10-20 — Step 2: the GameMenu call chain, per branch (VERIFIED)
- classic_era / classic_anniversary `GameMenuFrame.lua` are content-identical (181 lines).
  `InitButtons` `:62`, `GenerateMenuCallback` `:65`, closure `:66`, `callback()` **`:69`**,
  `Logout` `:158`, `Quit` `:159`. **The operator's stack (66/69) matches these exactly** →
  the report is from a classic-family client; Classic Era's numbering is the one that fits.
- classic_titan: OnShow `:36`→`:47`, InitButtons `:90`, closure `:94`, callback `:97`, Logout `:186`.
- forever: OnShow `:61`→`:72`, InitButtons `:158`, closure `:165`, callback `:168`, Logout `:263`.
- live: OnShow `:57`→`:68`, InitButtons `:113`, closure `:117`, callback `:120`, Logout `:215`.
- The closure is installed as a **button script**: `MainMenuFrameTemplates.lua:33`
  `newButton:SetScript("OnClick", callback);`; the buttons come from a pool parented to the
  GameMenu frame (`:14`).
- `GameMenuFrame` is `parent="UIParent"` on all five (xml `:4`, forever `:7`).
- `GameTooltip` is `parent="UIParent"` on all five — classic family
  `Blizzard_GameTooltip/Classic/GameTooltip.xml:13`, forever/live
  `Blizzard_GameTooltip/Mainline/GameTooltip.xml:249`. **(The brief had left
  forever/live unchecked; they are checked now.)**
- The refusal mechanism is engine-side and documented in the mirror:
  `RestrictedActionsDocumentation.lua:11-26` (`C_RestrictedActions.CheckAllowProtectedFunctions`)
  and `:83-92` (`ADDON_ACTION_FORBIDDEN` payload `{isTainted, function}`) — present on all five.

## 2026-10-20 — Step 3: Q4 / Q5 settled
- **Q4** `hooksecurefunc(table, method, hook)` is accepted on all five: Blizzard's own
  `Blizzard_Dispatcher.lua:260` uses that exact form on every branch. Our
  `Libs/LibDetours-1.0/LibDetours-1.0.lua:34/73` uses it for `SecureHook`.
  Caveat: it hooks **methods**; `OnShow`/`OnHide`/`OnTooltipSetUnit` are **scripts**, so
  `hooksecurefunc` cannot replace `Detours:ScriptHook` for them.
- **Q5** `GameTooltip.FadeOut` has **no Lua definition on any branch** (whole-tree sweep);
  Blizzard calls it unguarded on all five — classic family
  `Blizzard_UnitFrame/Classic/UnitFrame.lua:447`, forever `Mainline/UnitFrame.lua:393`,
  live `Mainline/UnitFrame.lua:386`. It is an **engine method present on all five**.
  → **`workshop.md`'s "exists only on live and forever" is WRONG**;
  `options.lua:483-506` and `main.lua:4792-4807` are RIGHT. The runtime probe
  `type(GameTooltip.FadeOut) == "function"` is therefore TRUE everywhere, and the
  `SecureHook` on `FadeOut` **is** installed on classic when `instant_fade` is on —
  but it is a `hooksecurefunc` post-hook, so it does not taint.

## 2026-10-20 — Step 4: taint inventory of our tree (VERIFIED)
- Always-on Blizzard-frame script hooks: `main.lua:2962` (OnTooltipSetUnit — **classic family
  only**), `:3211` (OnTooltipSetItem — classic only), `:3396` (OnTooltipSetSpell — classic only),
  `:3332/:3341/:3346` (OnTooltipCleared/OnShow/OnHide on GameTooltip + 9 tooltips),
  `:3805` (CharacterFrame OnShow), `:4054/:4067` (InspectFrame OnShow/OnHide).
- **Why classic-only for the first three:** the classic `GameTooltip` has no data-pipeline
  mixin (`Classic/GameTooltipTemplate.xml:22` mixin="GameTooltipMixin"; no
  `TooltipDataHandlerMixin`/`GameTooltipDataMixin` anywhere in the classic trees), so
  `dataPipelineActive()` (`main.lua:2887`) is false there and the addon falls back to raw
  `HookScript`. On live/forever the unit callback goes through the client's **secure**
  `TooltipDataProcessor.AddTooltipPostCall` → attribute delegate →
  `TooltipDataHandler.lua:181-201`.
- Conditional (mover / options / instant-fade) mutations of the shared GameTooltip:
  `main.lua:3596-3615`, `4854`, `5072/5075`, `5105-5106`, `5138-5141`, `5185`, `5202-5203`;
  `options.lua:1507/1515/1530`.
- `main.lua:3678-3685` (`GameTooltipStatusBar:HookScript`) **never runs** — there is no global
  `GameTooltipStatusBar` on any branch (only the mixin `GameTooltipStatusBarMixin` and the
  `$parentStatusBar` frame).
- Safe: `main.lua:3637` (`hooksecurefunc` on the global), `main.lua:4780` / `options.lua:530`
  (`Detours:SecureHook` → `hooksecurefunc`).
- **Structural link:** the shared `GameTooltip` is the tooltip Blizzard's own GameMenu buttons
  bind themselves to — `MainMenuFrameTemplates.lua:39` `GetAppropriateTooltip()` →
  `FrameUtil.lua:277-279` (classic_era) / `:289-291` (live) → `GameTooltip`. One object,
  two owners: our hooks and the quit path.

## 2026-10-20 — Step 5: the fix and the limits
- **Minimal fix:** wrap every addon callback that runs inside a Blizzard frame's script chain
  in `securecall` — `main.lua:2946`, `3332/3341/3346`, `5072/5075`, `3805/4054/4067`.
  Blizzard's own idiom for the same problem: `BuffFrame.lua:991`
  `securecall(self.UpdateDuration, self, self.timeLeft); -- Taint issue with SecondsToTimeAbbrev`.
  `securecall(` is present in the client source on all five branches (34/34/34/30/30 hits).
- **Cost:** one `securecall` per event; nothing the player sees changes; ≈10 lines in
  `main.lua`; no `.toc`, locale, harness or saved-variable change.
- **Residual risk (ASSUMED, not proven):** the taint-propagation rule itself is engine-side
  and is NOT written down anywhere in the FrameXML mirror. Blizzard states two of the needed
  rules in prose (`ChatFrameUtil.lua:58-59`; `ChatFrameFilters.lua:27-34`;
  `ChatFrameFiltersSecure.lua:5-6`) but the hop from the shared GameTooltip to the GameMenu
  button is inference. **One in-game A/B settles it:** disable the tooltip hooks, try to log out.
- **Dead end recorded:** the hypothesis "taint flows GameTooltip → UIParent → GameMenuFrame"
  does not survive contact with the source — `UIParent` is `protected="true"` on all three
  classic branches (`Blizzard_UIParent/Classic/UIParent.xml:4`) and is not in the XML at all
  on forever/live. The carrier that IS provable is the shared `GameTooltip` itself, because
  Blizzard's GameMenu buttons anchor to it.

## 2026-10-20 — [signal:done] quit-taint analysis landed
- **Worked on:** proved the GameMenu quit chain per branch from the client source, settled
  Q4/Q5, inventoried every taint-capable operation in our tree, named the minimal fix.
- **Current state:** bench artifact `bench/audits/2026-10-20-quit-taint.md` is written and
  labelled. **No product file was touched.** The tree is unchanged except for this desk and
  that one artifact.
- **Next step:** operator decision — run the one-session in-game A/B (disable the tooltip
  hooks, try to log out) to confirm the carrier before any product edit; and correct
  `workshop.md`'s `GameTooltip.FadeOut` bullet, which this audit proves wrong.
