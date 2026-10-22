# Taint Cross-Client — Journal

## 2026-10-21 — Desk opened
- **Purpose:** Cross-client verification of taint-relevant Blizzard globals against the client source mirror (`/home/sam/wow-ui-source`, `origin/`-qualified branches `classic_era`, `classic_anniversary`, `classic_titan`, `forever`, `live`).
- **Scope:** READ-ONLY client truth. Answers Q1-Q12 from the lane brief. Writes ONLY this desk directory and ONE bench artifact `bench/audits/2026-10-21-crossclient-taint-surfaces.md`.
- **Context:** the finding under test is `bench/audits/2026-10-21-quit-taint-carrier.md`.
- **Next step:** `@bench-read` the two prior audits as LEADS ONLY, then read the shipped tree (Q1) before touching the mirror.
- **Baseline captured:** `git status --short` (195 lines, pre-existing dirty tree) at `/tmp/opencode/taint-crossclient-baseline-status.txt`; mirror `git status --porcelain` (`?? .vscode/`, `?? SKILL.md`, `?? reference/`) at `/tmp/opencode/taint-crossclient-baseline-mirror.txt`.

## 2026-10-21 — Step 1: bench-read (prior findings as LEADS ONLY)
- **Read:** `bench/audits/2026-10-21-quit-taint-carrier.md` (275 lines) and `bench/audits/2026-10-20-quit-taint.md` (460 lines).
- **Leads carried forward (re-derived, not trusted):** the game-menu closure `PlaySound`/`HideUIPanel`/`callback()`; the `PlaySound` global detour in the vendored `LibForeverInspector` (now removed); `hooksecurefunc` does not replace; `securecall` is the containment primitive; `GameTooltipStatusBar` claimed to be a non-existent global (that 2026-10-20 audit asserted an ABSENCE — I re-swept it; see Step 5, and it does NOT hold up).
- **Current state:** desk open, journal started, no client command run yet.
- **Next step:** Q1 — enumerate every Blizzard global the shipped tree replaces/wraps, reading the repo source (not the audits).

## 2026-10-21 — Step 2: Q1 global inventory (repo source, not the audits)
- **Method:** grep over the shipped tree (`main.lua`, `options.lua`, `gearscore.lua`, `textures.lua`, `pawn.lua`, `TacoTip_Extras/*.lua`, `Libs/LibDetours-1.0`, `Libs/LibForeverInspector`, `Libs/LibStub`, `Libs/CallbackHandler-1.0`). `OLD/` and `Tests/` excluded (not shipped). `TacoTip.toc` and `TacoTip_Extras/TacoTip_Extras.toc` read to confirm which files ship.
- **Blizzard GLOBALS REPLACED (`rawset(_G, ...)`):**
  1. `GetGameMessageInfo` — `Libs/LibForeverInspector/LibForeverInspector.lua:5042` (`Detours:DetourHook(lib, "GetGameMessageInfo", ...)` → `Libs/LibDetours-1.0/LibDetours-1.0.lua:134 rawset(_G, funcName, func)`). CONDITIONAL: `isClassic` (Classic Era only) at `:5022` + `:177`, AND `type(_G.GetGameMessageInfo)=="function"` at `:5041`.
  2. `PlayVocalErrorSoundID` — `Libs/LibForeverInspector/LibForeverInspector.lua:5035` (same detour mechanism). CONDITIONAL: `isClassic` AND `type(_G.PlayVocalErrorSoundID)=="function"` at `:5034`.
  3. `InspectGuildFrame_Update` — `main.lua:4087 rawset(_G, "InspectGuildFrame_Update", function(...) ...)`. CONDITIONAL: `type(rawget(_G,"InspectGuildFrame_Update"))=="function"` at `:4083-4084` and not already guarded at `:4085`; installed from `main.lua:4110`.
  4. `SlashCmdList` — `options.lua:700` and `gearscore.lua:226 rawset(_G, "SlashCmdList", slashCmdList)`. FALLBACK ONLY: runs only when `rawget(_G,"SlashCmdList")` is nil (`options.lua:697-698`).
- **Blizzard TABLE FIELDS replaced (not `_G` entries, but Blizzard-owned):** `UIErrorsFrame.AddMessage` (`LibForeverInspector.lua:5027` → `LibDetours:123 funcTable[funcName] = func`) and `C_Sound.PlayVocalErrorSound` (`:5030`). Both Classic Era only.
- **Mixin (ADDS fields, never replaces):** `main.lua:568 Mixin(_G.GameTooltip, _G.BackdropTemplateMixin)` (CONDITIONAL on no `NineSlice` and no `SetBackdrop`); `main.lua:1090 Mixin(tooltip, BackdropTemplateMixin)` (CONDITIONAL on `not tooltip.SetBackdrop`).
- **hooksecurefunc (does NOT replace):** `main.lua:3726` (`"GameTooltip_SetDefaultAnchor"`, global-name form); `main.lua:4901` + `options.lua:568` (`Detours:SecureHook(TT, GameTooltip, "FadeOut", ...)` → `LibDetours:73 hooksecurefunc(funcTable, funcName, ...)`); `TacoTip_Extras/Frames.lua:1375/1377` (`safeSecureHook` on `InspectFrame_Show`, `InspectFrame_UnitChanged`, `InspectSwitchTabs`).
- **NOT a global replacement but a Blizzard-table write:** `main.lua:5154 rawset(StaticPopupDialogs, "_TacoTipDragButtonConfirm_", {...})` (adds ONE key); `options.lua:713` / `gearscore.lua:240 rawset(slashCmdList, "TACOTIP", fn)` (adds ONE key to the `SlashCmdList` table).
- **No `_G.NAME =` assignment replaces any Blizzard global.** Every `_G.X =` in the tree writes an addon-owned name (`TacoTip`, `TT_GS`, `TACOTIP_LOCALES`, `TacoTipExtrasDB`, `SLASH_TACOTIPRANKS*`, `SLASH_TTEXTRAS*`, `TacoTipExtrasPrintDebugSnapshot`, `_tacoTipInspectGuildGuarded`).
- **NOT SHIPPED:** `Libs/LibDBIcon-1.0/` and `Libs/LibDataBroker-1.1/` are in the repo but in NO `.toc` — not part of the shipped tree.
- **Current state:** Q1 complete from source.
- **Next step:** Q2 — the game menu call graph, per branch.

## 2026-10-21 — Step 3: Q2 the game menu call graph (per branch)
- **Method:** `git -C /home/sam/wow-ui-source show origin/<branch>:<path>` for `Blizzard_GameMenu/Shared/GameMenuFrame.lua`, `Blizzard_GameMenu/Shared/GameMenuFrame.xml`, `Blizzard_SharedXML/Shared/Frame/MainMenuFrameTemplates.lua`, plus the per-branch tocs.
- **classic_era:** `GameMenuFrame.lua:65-71` closure — `PlaySound` `:67`, `HideUIPanel(self)` `:68`, `callback()` `:69`; Logout `:158`, Quit `:159`; `StaticPopup_Visible("QUIT")` `:157`; `MainMenuFrameTemplates.lua:68` `PlaySound(SOUNDKIT.IG_MAINMENU_CONTINUE)` in `AddCloseButton`.
- **classic_anniversary:** same file, same lines — verified separately: `GameMenuFrame.lua:65-71`, `PlaySound` `:67`, `HideUIPanel` `:68`, `callback()` `:69`, Logout `:158`, Quit `:159`, `StaticPopup_Visible("QUIT")` `:157`, `MainMenuFrameTemplates.lua:68` `PlaySound`.
- **classic_titan:** `GameMenuFrame.lua:93-99` closure — `PlaySound` `:95`, `HideUIPanel` `:96`, `callback()` `:97`; Logout `:186`, Quit `:187`; `StaticPopup_Visible("QUIT")` `:185`; WRITES `StaticPopupDialogs["GAMEMENU_EXTERNALEVENT_FAILURE"]` at `:6`; `StaticPopup_Show("GAMEMENU_EXTERNALEVENT_FAILURE")` at `:87`; `MainMenuFrameTemplates.lua:68` `PlaySound`.
- **forever:** `GameMenuFrame.lua:164-170` closure — `PlaySound` `:166`, `HideUIPanel` `:167`, `callback()` `:168`; Logout `:263`, Quit `:264`; `StaticPopup_Visible("QUIT")` `:262`; WRITES `StaticPopupDialogs[...]` at `:6`; `StaticPopup_Show(...)` at `:123`; PLUS `PlaySound(SOUNDKIT.IG_MAINMENU_QUIT)` `:31` and `PlaySound(SOUNDKIT.IG_MAINMENU_OPEN)` `:39`; `MainMenuFrameTemplates.lua:81` `PlaySound`.
- **live:** `GameMenuFrame.lua:116-122` closure — `PlaySound` `:118`, `HideUIPanel` `:119`, `callback()` `:120`; Logout `:215`, Quit `:216`; `StaticPopup_Visible("QUIT")` `:214`; WRITES `StaticPopupDialogs[...]` at `:6`; `StaticPopup_Show(...)` at `:110`; PLUS `PlaySound(SOUNDKIT.IG_MAINMENU_QUIT)` `:31` and `PlaySound(SOUNDKIT.IG_MAINMENU_OPEN)` `:39`; `MainMenuFrameTemplates.lua:76` `PlaySound`.
- **Collision check:** NONE of the globals the game menu path calls is replaced by the shipped tree. The only overlaps are ADDITIVE (Mixin onto `GameTooltip`, `hooksecurefunc` onto `GameTooltip_SetDefaultAnchor`, one added key in `StaticPopupDialogs`).
- **Current state:** Q2 complete.
- **Next step:** Q3 — `GameTooltipStatusBar`, whole-tree sweep + generated API docs, per branch.

## 2026-10-21 — Step 4: Q3 `GameTooltipStatusBar` (per branch) — the prior audit's absence claim does NOT hold
- **Whole-tree sweep for the literal identifier `GameTooltipStatusBar`, all branches, whole tree (not only `Interface/`):** classic_era: 3 hits, all `GameTooltipStatusBarMixin` + the `$parentStatusBar` XML child. classic_anniversary: 3 hits, same. classic_titan: 3 hits, same. forever: 0 hits. live: 0 hits.
- **Generated API docs sweep (`Blizzard_APIDocumentationGenerated/`, 535/535/535/641/623 files on classic_era/classic_anniversary/classic_titan/forever/live):** 0 hits on every branch.
- **BUT the `$parentStatusBar` template child exists on ALL FIVE branches:** classic_era `Blizzard_SharedXML/Classic/GameTooltipTemplate.xml:138`; classic_anniversary `Blizzard_SharedXML/Classic/GameTooltipTemplate.xml:138`; classic_titan `Blizzard_SharedXML/Classic/GameTooltipTemplate.xml:138`; forever `Blizzard_GameTooltip/Mainline/GameTooltip.xml:9`; live `Blizzard_GameTooltip/Mainline/GameTooltip.xml:9`. The `GameTooltip` frame inherits that template on all five (classic_era/anniversary/titan `Blizzard_GameTooltip/Classic/GameTooltip.xml:13`; forever/live `Blizzard_GameTooltip/Mainline/GameTooltip.xml:249`).
- **The `$parent`→global mechanism is demonstrated in the SAME files:** `$parentTextLeft1` resolves to the global `GameTooltipTextLeft1`, and Blizzard's own Lua uses it as a bare global on every branch — classic_era `Blizzard_AuctionHouseUI/Shared/Blizzard_AuctionHouseBuyDialog.lua:36,:47`, `Blizzard_UnitFrame/Classic/UnitFrame.lua:460`; classic_anniversary same three; classic_titan same three; forever `Blizzard_AuctionHouseUI/Shared/Blizzard_AuctionHouseBuyDialog.lua:36,:47` + `Blizzard_UIPanels_Game/Mainline/QuestMapFrame.lua:2223`; live `Blizzard_AuctionHouseUI/Shared/Blizzard_AuctionHouseBuyDialog.lua:36,:47` + `Blizzard_UIPanels_Game/Mainline/QuestMapFrame.lua:2124`.
- **Per-branch mixin on that StatusBar differs:** classic_era `GameTooltipStatusBarMixin` (`Blizzard_SharedXML/Classic/GameTooltipTemplate.lua:25`); classic_anniversary same; classic_titan same; forever `GameTooltipUnitHealthBarMixin`; live `GameTooltipUnitHealthBarMixin`.
- **Our tree uses the name in three places:** `main.lua:1642-1643`, `main.lua:2818-2819`, `main.lua:3789-3796` (`GameTooltipStatusBar:HookScript("OnHide", ...)` — an addon script hook on a Blizzard frame).
- **Current state:** Q3 answered per branch with the evidence level stated in the artifact.
- **Next step:** Q4/Q11 — the backdrop API surface per branch.

## 2026-10-21 — Step 5: Q4 + Q11 backdrop API surface (per branch)
- **classic_era:** `GameTooltipTemplate` inherits `GameTooltipCommonTemplate, TooltipBackdropTemplate` (`Blizzard_SharedXML/Classic/GameTooltipTemplate.xml:22`); `TooltipBackdropTemplate` has `<Frame parentKey="NineSlice" inherits="NineSlicePanelTemplate" useParentLevel="true"/>` (`Blizzard_SharedXML/SharedTooltipTemplates.xml:109`) → **NineSlice EXISTS**; `TooltipBackdropTemplate` mixes in `TooltipBackdropTemplateMixin` only (`SharedTooltipTemplates.xml:104`), which provides `SetBackdropColor`/`SetBackdropBorderColor`/`SetBorderBlendMode` (`SharedTooltipTemplates.lua:243,:251,:259`) but **NOT `SetBackdrop`** → `GameTooltip.SetBackdrop` is **nil**.
- **classic_anniversary:** same three citations, verified separately → NineSlice EXISTS, `SetBackdrop` nil.
- **classic_titan:** same three citations, verified separately → NineSlice EXISTS, `SetBackdrop` nil.
- **forever:** `GameTooltipTemplate` inherits `SharedTooltipTemplate` (`Blizzard_GameTooltip/Mainline/GameTooltip.xml:4`); `SharedTooltipTemplate` inherits `SharedTooltipArtTemplate` (`Blizzard_SharedXML/SharedTooltipTemplates.xml:95`); `SharedTooltipArtTemplate` has `<Frame parentKey="NineSlice" .../>` (`SharedTooltipTemplates.xml:19`) → **NineSlice EXISTS**; `SharedTooltipArtTemplate` carries no `mixin` → **`SetBackdrop` nil**.
- **live:** same three citations, verified separately → NineSlice EXISTS, `SetBackdrop` nil.
- **`BackdropTemplateMixin:SetBackdrop` exists on all five** (`Blizzard_SharedXML/Backdrop.lua:336` on every branch) — that is the method `Mixin(GameTooltip, BackdropTemplateMixin)` would graft.
- **Consequence:** `main.lua:563-568`'s guard needs `not _G.GameTooltip.NineSlice`; NineSlice exists on every branch → **the `Mixin(_G.GameTooltip, _G.BackdropTemplateMixin)` guard fires on NO branch**, and `main.lua:1089-1091`'s per-tooltip Mixin does not fire either (`main.lua:1075` takes the NineSlice branch).
- **Current state:** Q4 and Q11 answered per branch.
- **Next step:** Q5/Q12 — `InspectGuildFrame_Update`, per branch.

## 2026-10-21 — Step 6: Q5 + Q12 `InspectGuildFrame_Update` (per branch)
- **classic_era:** 0 hits in the whole tree AND 0 in the generated API docs → the global does not exist on this branch. `main.lua:4083` `rawget(_G, "InspectGuildFrame_Update")` → nil → `main.lua:4084` returns false → **no replacement on classic_era**.
- **classic_anniversary:** 0 hits, 0 API-doc hits → does not exist → no replacement.
- **classic_titan:** 0 hits, 0 API-doc hits → does not exist → no replacement.
- **forever:** Lua-defined global at `Blizzard_InspectUI/Mainline/InspectGuildFrame.lua:17` (and a `Camelot/` variant at `Blizzard_InspectUI/Camelot/InspectGuildFrame.lua:17`), 0 API-doc hits → it is a **Lua** function, not an engine function → `main.lua:4087` **DOES replace it on forever**.
- **live:** Lua-defined global at `Blizzard_InspectUI/Mainline/InspectGuildFrame.lua:17`, 0 API-doc hits → Lua function → `main.lua:4087` **DOES replace it on live**.
- **Game menu reachability:** 0 hits for `InspectGuildFrame_Update` inside `Interface/AddOns/Blizzard_GameMenu/` on every branch → never on the game menu path.
- **Current state:** Q5 and Q12 answered per branch.
- **Next step:** Q6 — `StaticPopupDialogs` on the game menu path, per branch.

## 2026-10-21 — Step 7: Q6 `StaticPopupDialogs` (per branch)
- **`StaticPopupDialogs` is a Blizzard table on all five:** `Blizzard_StaticPopup/StaticPopup.lua:21 StaticPopupDialogs = {}; -- Definitions` (classic_era, classic_anniversary, classic_titan, forever, live — same line).
- **`StaticPopup_Visible` does NOT read the table:** `Blizzard_StaticPopup/StaticPopup.lua:140-151` — `SecureStaticPopup_Visible` walks the LOCAL `shownDialogFrames`; `StaticPopup_Visible` wraps it in `securecallfunction`. So the game menu's `StaticPopup_Visible("QUIT")` does not touch `StaticPopupDialogs`.
- **`StaticPopup_Show` DOES read the table:** `StaticPopup.lua:279 local dialogInfo = StaticPopupDialogs[which];` (also `:127` in `StaticPopup_FindVisible`, `:265`, `:442`, `:558`, `:593`, `:622`, `:649`, `:743`, `:769`, `:785`, `:928`).
- **Per branch, the game menu path touches `StaticPopupDialogs`:** classic_era — NO (only `StaticPopup_Visible` at `GameMenuFrame.lua:157`). classic_anniversary — NO (same). classic_titan — YES (WRITES at `GameMenuFrame.lua:6`, READS via `StaticPopup_Show` at `:87`). forever — YES (WRITES `:6`, READS via `StaticPopup_Show` `:123`). live — YES (WRITES `:6`, READS via `StaticPopup_Show` `:110`).
- **Our write** `main.lua:5154 rawset(StaticPopupDialogs, "_TacoTipDragButtonConfirm_", {...})` adds ONE key; it does not replace the table and does not touch any existing key.
- **Current state:** Q6 answered per branch.
- **Next step:** Q7/Q10 — `securecall` per branch.

## 2026-10-21 — Step 8: Q7 + Q10 `securecall` (per branch)
- **Count of literal `securecall(` occurrences, whole `Interface/` tree** (`git grep -o "securecall(" origin/<branch> -- 'Interface/' | wc -l`): classic_era 174, classic_anniversary 174, classic_titan 174, forever 124, live 123. (The 2026-10-20 audit's "34×/30×" figure does not reproduce under this command.)
- **Captured as a local on every branch:** `local securecall = securecall;` — classic_era `Blizzard_FrameXML/SharedPetBattleTemplates.lua:5`; classic_anniversary same; classic_titan same; forever same; live same (also `Blizzard_RestrictedAddOnEnvironment/RestrictedFrames.lua:22` and `SecureHandlers.lua:17` on every branch). No Lua definition of `securecall` exists anywhere → it is an engine global.
- **Two shapes, both present on every branch:**
  - STRING-first (calls a global by name): classic_era `Blizzard_CatalogShop/Blizzard_CatalogShop_Outbound.lua:9 securecall("UpdateMicroButtons");`; classic_anniversary same; classic_titan same; forever same; live same. classic_era/anniversary/titan also `Blizzard_StoreUI/Classic/Blizzard_StoreUIOutbound.lua:25 securecall("Logout");`; forever `Blizzard_StoreUI/Blizzard_Shared_StoreUIOutbound.lua:21`; live same.
  - FUNCTION-first (calls a function value): classic_era `Blizzard_BuffFrame/BuffFrame.lua:991 securecall(self.UpdateDuration, self, self.timeLeft);`; classic_anniversary `:991`; classic_titan `:991`; forever `Blizzard_BuffFrame/BuffFrame.lua:1235`; live `Blizzard_BuffFrame/BuffFrame.lua:961`.
- **String-first counts:** classic_era 131, classic_anniversary 131, classic_titan 131, forever 81, live 80.
- **Current state:** Q7 and Q10 answered per branch.
- **Next step:** Q9 — `GetGameMessageInfo` callers per branch.

## 2026-10-21 — Step 9: Q9 `GetGameMessageInfo` callers (per branch)
- **It is a documented engine global on all five:** `Blizzard_APIDocumentationGenerated/GameErrorDocumentation.lua:10 Name = "GetGameMessageInfo"` (classic_era, classic_anniversary, classic_titan, forever, live).
- **Callers (whole `Interface/` tree):**
  - classic_era: `Blizzard_Channels/VoiceUtils.lua:82`; `Blizzard_UIErrorsFrame/Classic/UIErrorsFrame.lua:142`.
  - classic_anniversary: `Blizzard_Channels/VoiceUtils.lua:82`; `Blizzard_UIErrorsFrame/Classic/UIErrorsFrame.lua:142`.
  - classic_titan: `Blizzard_Channels/VoiceUtils.lua:82`; `Blizzard_UIErrorsFrame/Classic/UIErrorsFrame.lua:142`.
  - forever: `Blizzard_Channels/Classic/VoiceUtils.lua:82`; `Blizzard_Channels/Mainline/VoiceUtils.lua:88`; `Blizzard_UIErrorsFrame/Mainline/UIErrorsFrame.lua:150` — **THREE callers on forever**, not two.
  - live: `Blizzard_Channels/VoiceUtils.lua:82`; `Blizzard_UIErrorsFrame/Mainline/UIErrorsFrame.lua:150`.
- **Every call site uses the bare global**, so `rawset(_G, "GetGameMessageInfo", ...)` replaces the exact binding the client calls.
- **Reachable from the game menu Logout/Quit path? NO on every branch:** 0 hits for `GetGameMessageInfo`, `UIErrorsFrame` or `VoiceUtils` inside `Interface/AddOns/Blizzard_GameMenu/` on classic_era, classic_anniversary, classic_titan, forever, live.
- **Current state:** Q9 answered per branch.
- **Next step:** Q8 — the shared GameTooltip script set per branch.

## 2026-10-21 — Step 10: Q8 shared GameTooltip script set (per branch)
- **classic_era:** frame block `Blizzard_GameTooltip/Classic/GameTooltip.xml:14-34` declares `OnLoad` `:15-21`, `OnTooltipSetUnit` `:22`, `OnTooltipSetItem` `:23`, `OnTooltipSetSpell` `:24`, `OnHide` `:25-32`, `OnUpdate` `:33`; template block `Blizzard_SharedXML/Classic/GameTooltipTemplate.xml:150-156` declares `OnLoad` `:151`, `OnHide` `:152`, `OnTooltipSetDefaultAnchor` `:153`, `OnTooltipAddMoney` `:154`, `OnTooltipCleared` `:155`. **`OnShow` is NOT declared on classic_era.**
- **classic_anniversary:** identical citations, verified separately — `OnShow` NOT declared.
- **classic_titan:** identical citations, verified separately — `OnShow` NOT declared.
- **forever:** template `Blizzard_GameTooltip/Mainline/GameTooltip.xml:25-36` declares `OnLoad` `:26`, `OnHide` `:27`, `OnTooltipSetDefaultAnchor` `:28-30`, `OnTooltipCleared` `:31-34`, `OnEvent` `:35`; shared-template `Blizzard_SharedXML/SharedTooltipTemplates.xml:96-101` declares `OnLoad` `:97`, `OnHide` `:98`, `OnTooltipSetDefaultAnchor` `:99`, `OnTooltipCleared` `:100`; frame `Blizzard_GameTooltip/Mainline/GameTooltip.xml:269-273` declares `OnLoad` `:270`, `OnShow` `:271`, `OnUpdate` `:272`. **`OnTooltipSetUnit` / `OnTooltipSetItem` / `OnTooltipSetSpell` are NOT declared on forever.**
- **live:** identical citations, verified separately — `OnTooltipSetUnit`/`SetItem`/`SetSpell` NOT declared.
- **Current state:** Q8 answered per branch.
- **Next step:** write the bench artifact, run the validation bar, emit the `done` signal.

## 2026-10-21 — Step 11: validation bar + artifact + signal
- **Written:** `bench/audits/2026-10-21-crossclient-taint-surfaces.md` (the ONE bench artifact this lane owns).
- **Validation 1 — mirror untouched:** `git -C /home/sam/wow-ui-source status --porcelain` → `?? .vscode/`, `?? SKILL.md`, `?? reference/` — identical to the baseline captured at desk-open (same three untracked entries, nothing else).
- **Validation 2 — no product file touched:** `git -C /home/sam/TacoTip-Gearscore-TBC status --short` → diffed against the baseline; the only NEW entries are `?? desks/taint-crossclient-2026-10-21/` and `?? bench/audits/2026-10-21-crossclient-taint-surfaces.md`. No product file changed.
- **Validation 3 — every `path:line` came from a command run in this lane** (recorded with the command in the artifact).
- **Validation 4 — every client claim names its branch and carries an evidence label** (VERIFIED / ASSUMED / UNKNOWN per `CAIRN.md`).
- **Signal:** `done`, `signal_type: "execution"`, `subtype: "done"`, `run_id: taintcrossclient20261021`.

## 2026-10-21 — [signal:done] cross-client taint surfaces landed
- **Artifact:** `bench/audits/2026-10-21-crossclient-taint-surfaces.md` (the ONE bench artifact this lane owns).
- **Signal:** `desks/taint-crossclient-2026-10-21/.signals/2026-10-21T13:20:04Z.json` — `signal_type: "execution"`, `subtype: "done"`, `run_id: taintcrossclient20261021`.
- **Headline:** the shipped tree replaces **no** global the game menu path touches, on **classic_era, classic_anniversary, classic_titan, forever or live**. The replaced set is `GetGameMessageInfo` (classic_era only), `PlayVocalErrorSoundID` (classic_era only), `InspectGuildFrame_Update` (forever, live only), `SlashCmdList` (fallback only) — plus two Blizzard table fields on classic_era (`UIErrorsFrame.AddMessage`, `C_Sound.PlayVocalErrorSound`).
- **Corrections filed:** the 2026-10-20 audit's "`GameTooltipStatusBar` does not exist on any branch" absence claim is withdrawn (§11.1); "exactly two `GetGameMessageInfo` callers" is wrong on forever — three (§11.2); the `securecall(` count 34/30 does not reproduce — 174/174/174/124/123 (§11.3); `main.lua`'s "legacy template without NineSlice" fallback matches no shipped client (§11.4).
- **Validation 1 (mirror):** `git -C /home/sam/wow-ui-source status --porcelain` → `?? .vscode/`, `?? SKILL.md`, `?? reference/` — byte-identical to the desk-open baseline (diff empty). **PASS.**
- **Validation 2 (repo):** `git status --short` differs from the baseline only by `?? bench/audits/2026-10-21-crossclient-taint-surfaces.md` and `?? desks/taint-crossclient-2026-10-21/`. No product file changed. **PASS.**
- **Validation 3:** every `path:line` came from a command run in this lane (steps 2-10 above). **PASS.**
- **Validation 4:** every client claim names its branch and carries VERIFIED / ASSUMED / UNKNOWN. **PASS.**
- **Open, for the next lane:** Q3's last step — whether a `<Frames>` child with a `name` is registered as a Lua global the way the `<Layers>` sibling `$parentTextLeft1` is — is **ASSUMED**, not verified, and it is the only thing standing between "`main.lua:3789` is dead code" and "`main.lua:3789` installs an add-on `OnHide` hook on a Blizzard frame at load time". An in-game check on classic_era (`/dump _G.GameTooltipStatusBar`) would settle it; the mirror cannot.
