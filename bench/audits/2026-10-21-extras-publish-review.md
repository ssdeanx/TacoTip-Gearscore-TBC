# TacoTip Extras — publish-ready review (five clients, v1.2.3)

- **desk:** `extras-publish-review-2026-10-21` · **date:** 2026-10-21 · **run_id:** `extraspublishreview20261021`
- **kind:** READ-ONLY review. **No product file was edited.** The only writes are
  this artifact and `desks/extras-publish-review-2026-10-21/` (journal + one
  `done` signal).
- **scope:** `TacoTip_Extras/` only — Core, Scoring, Cache, RankDB, RankSync,
  Scanner, TacoTipAdapter, Tooltips, Frames, RankBrowser, Minimap, Options,
  `Locale/*.lua` (11), `TacoTip_Extras.toc`, `Tests/harness/`.
- **clients:** FIVE separate clients, every claim branch-qualified:
  `classic_era` (11509), `classic_anniversary` (20506), `classic_titan` (38002),
  `forever` (16001), `live` (120105).
- **evidence labels:** VERIFIED / ASSUMED / UNKNOWN per `CAIRN.md`.
- **method:** `git -C /home/sam/wow-ui-source show origin/<branch>:<path>` and
  `git grep` (read-only); XML parsed with a namespace-aware parser so the
  `<Scripts>` blocks quoted below are the client's own, not a grep's guess.
  No web. No state-changing git.
- **supersedes:** nothing. It does **not** supersede
  `bench/audits/2026-10-21-quit-taint-carrier.md`; that artifact's §5 class
  ("wrap every callback that enters a Blizzard frame's script chain") is
  **confirmed for the Extras** by §11 below, with three named gaps.

---

## 0. Summary

| | result |
|---|---|
| Extras harness | **42 / 42 PASS** on all three interpreters (`bash TacoTip_Extras/Tests/harness/run_all.sh`) |
| `luacheck TacoTip_Extras` | **0 warnings / 0 errors in 26 files** |
| `Tools/verify_release_extras.sh --worktree` | **PASS** — 29 files, 23 TOC-listed runtime files, icon present, no PNG / no `Tests/` |
| Saved-variable shape | stable, schema 2, no write-then-fail-to-read in the shipped path |
| Whisper path | **still deleted** — no `SendChatMessage`, no whisper transport anywhere |
| Locale parity | **same 154-key set in all 11 locales**; key ORDER differs in `zhTW` (5 positions) and `enUS` (all) |
| Containment (`Core.RunUntainted`) | present at every Blizzard script-chain entry **except three**, named in §11 |
| **Blocking findings** | **0 confirmed.** 1 item cannot be settled from the mirror and is escalated in §12 with a one-line in-game probe |
| **Should-fix** | 4 (one of them the §12 escalation) |
| **Nit** | 6 |

---

## 1. A1 — every Blizzard-object interaction in the package

**Whole-package sweeps run** (all under `TacoTip_Extras/`, `Tests/` excluded):

    grep -rn "HookScript" | grep -v "^./Tests/"      ->  Frames.lua, Options.lua, Tooltips.lua
    grep -rn ":SetScript("                            ->  Minimap/Frames/Core/Options/RankBrowser/RankSync
    grep -rn "hooksecurefunc"                         ->  TacoTipAdapter.lua:742,812 ; Frames.lua:1370,1375,1377
    grep -rn "Detour"                                 ->  (0 hits)
    grep -rn "rawset"                                 ->  Core.lua:1291 ; RankBrowser.lua:2992-3038
    grep -rn "Mixin("                                 ->  (0 hits)
    grep -rn "CreateFrame("                           ->  Minimap, Frames, Core, Options, RankBrowser, RankSync

**There is no `Detours:DetourHook`, no `Mixin(...)`, and no `rawset` onto a
Blizzard global anywhere in the package.** VERIFIED. Every `rawset` targets a
NEW global of the add-on's own (`TacoTipExtrasPrintDebugSnapshot`,
`SLASH_TACOTIPRANKS1..7`, `TacoTipExtrasToggleLeaderboard`). VERIFIED.

### 1.1 The inventory

| # | file:line | Blizzard object | operation | always-on / conditional / dead | enters a Blizzard SCRIPT CHAIN? | contained by `Core.RunUntainted`? |
|---|---|---|---|---|---|---|
| 1 | `Frames.lua:1352` | `PaperDollFrame` (Blizzard) | `HookScript("OnShow", …)` | always-on (installed) / **the hook can NEVER fire** (§3) | **yes** (the frame's own script chain) | **yes** (`boundedCallback` → `Core.RunUntainted`, `Frames.lua:92`) |
| 2 | `Frames.lua:1353` | `PaperDollFrame` | `HookScript("OnHide", …)` | always-on / **can NEVER fire** (§3) | yes | yes |
| 3 | `Frames.lua:1356` | `PaperDollFrame` | `HookScript("OnSizeChanged", …)` | always-on | yes | yes |
| 4 | `Frames.lua:1401` | `InspectPaperDollFrame` (Blizzard) | `HookScript("OnShow", …)` | always-on / **CAN fire** (§3) | yes | yes |
| 5 | `Frames.lua:1402` | `InspectPaperDollFrame` | `HookScript("OnHide", …)` | always-on / **CAN fire** (§3) | yes | yes |
| 6 | `Frames.lua:1405` | `InspectPaperDollFrame` | `HookScript("OnSizeChanged", …)` | always-on | yes | yes |
| 7 | `Frames.lua:1410` | `InspectFrame` (Blizzard) | `HookScript("OnShow", …)` | always-on / **CAN fire** (§3) | yes | yes |
| 8 | `Frames.lua:1415` | `InspectFrame` | `HookScript("OnHide", …)` | always-on / **CAN fire** (§3) | yes | yes |
| 9 | `Frames.lua:1418-1420` | global `InspectFrame_Show` | `hooksecurefunc` post-hook | always-on / **CAN fire** (§2) | **no** (called from `InspectUnit`, a plain global) — but the post-hook body still runs as addon code in the caller's chain | **yes** |
| 10 | `Frames.lua:1421-1423` | global `InspectFrame_UnitChanged` | `hooksecurefunc` post-hook | always-on / **DEAD on all five clients** (§2) | no | yes (vacuously) |
| 11 | `Frames.lua:1424-1430` | global `InspectSwitchTabs` | `hooksecurefunc` post-hook | always-on / **CAN fire** (§2) | **YES** — called from the tab Button's `<OnClick>` | **yes** |
| 12 | `Tooltips.lua:1689-1700` | shared `GameTooltip` | `HookScript` × 4 (`OnTooltipSetUnit`, `OnTooltipSetItem`, `OnTooltipCleared`, `OnHide`) | always-on, each **guarded by `HasScript`** (`Tooltips.lua:1692`) and by `pcall` | **yes** | **yes** (`contained` → `Core.RunUntainted`, `Tooltips.lua:1671`) |
| 13 | `Tooltips.lua:1705-1709` | shared `GameTooltip` | `HookScript("OnUpdate", …)` (poll) | **conditional**: only when `OnTooltipSetUnit` is absent (§4) | **yes** | yes |
| 14 | `Tooltips.lua:1727-1728` | shared `GameTooltip` | `HookScript("OnShow", …)` (poll arm) | **conditional**: poll mode only | yes | yes |
| 15 | `Tooltips.lua:1746-1760` | Blizzard global table `TooltipDataProcessor` | `AddTooltipPostCall(Unit, fn)` | always-on (guarded by 4 capability checks) | **it is a Blizzard-DISPATCHED callback** — the client's own post-call runs it | **NO — see §11.3 (F3)** |
| 16 | `TacoTipAdapter.lua:1541-1546` | **TacoTip (the other add-on)**, not Blizzard | `hooksecurefunc(tacoTip, "RefreshCharacterFrame"/"RefreshInspectFrame", cb)` | conditional (only when TacoTip is loaded and compatible) | not a Blizzard frame; the body may run inside whatever chain TacoTip calls from | **NO — see §1.3 (F5)**; the body is `pcall`-guarded internally |
| 17 | `Tooltips.lua:1254-1268` (`target:AddLine`) | shared `GameTooltip` | data write | conditional (a render) | no — called from the add-on's own render path | n/a (the caller is contained) |
| 18 | `Options.lua:558-592` | shared `GameTooltip` | `ClearLines` / `SetOwner` / `ClearAllPoints` / `SetPoint` / `SetText` / `AddLine` / `Show` | conditional (options-panel hover) | **no** — the script chain is the add-on's own help `region` frame | n/a (not a Blizzard chain) — **F4** |
| 19 | `Options.lua:504-526` | shared `GameTooltip` | `Hide` / `ClearLines` / `ClearAllPoints` | conditional | no | n/a — **F4** |
| 20 | `Minimap.lua:149-165` | shared `GameTooltip` | `SetOwner` / `SetText` / `AddLine` / `Show` | conditional (minimap-button hover) | no — the chain is the add-on's own button | n/a — **F4** |
| 21 | `Minimap.lua:167-172` | shared `GameTooltip` | `Hide` | conditional | no | n/a — **F4** |
| 22 | `RankBrowser.lua:843-915` | shared `GameTooltip` | `SetOwner` / `ClearLines` / `AddLine` | conditional (row hover) | no — the chain is the add-on's own row | n/a — **F4** |
| 23 | `RankBrowser.lua:917-922` | shared `GameTooltip` | `Hide` | conditional | no | n/a — **F4** |
| 24 | `TacoTipAdapter.lua:699-711`, called at `:1026`/`:1043` | TacoTip's OWN `PersonalGearScore…` / `InspectGearScore…` font strings and their `mover` buttons (objects that LIVE under the Blizzard `PaperDollFrame` / `InspectPaperDollFrame`) | `Show()` / `Hide()` | conditional (gear panel lease) | no | n/a |
| 25 | `Core.lua:885`, `:1361`; `Options.lua:1541`; `RankBrowser.lua:1176`; `Scanner.lua:1348`; `TacoTipAdapter.lua:1655`; `Tooltips.lua:154` | Blizzard `DEFAULT_CHAT_FRAME` | `AddMessage` (data write) | conditional | no | n/a |
| 26 | `Frames.lua:1290-1294` | **`CreateFrame("Frame", …, context.host)`** — an ADD-ON frame parented to the Blizzard `PaperDollFrame` / `InspectPaperDollFrame` | frame creation | always-on (when the surface binds) | the new frame is the add-on's own | n/a |
| 27 | `Frames.lua:1300` | `block:CreateFontString(…, "GameFontHighlightSmall")` | font string under the ADD-ON block | always-on | n/a | n/a |
| 28 | `Frames.lua:1312-1317` | `CreateFrame("Button", …, block, "UIPanelButtonTemplate")` | add-on handle under the add-on block, **Blizzard template** | always-on | n/a (template only) | n/a |
| 29 | `Minimap.lua:188-192` | **`CreateFrame("Button", "TacoTip_ExtrasMinimapButton", _G.Minimap)`** — an ADD-ON button parented to the Blizzard `Minimap` | frame creation | always-on when the minimap surface initialises | n/a | n/a |
| 30 | `Minimap.lua:206-222` | `button:CreateTexture(…)` ×3, `SetHighlightTexture` | textures under the ADD-ON button | always-on | n/a | n/a |
| 31 | `Minimap.lua:223-227` | the ADD-ON button | `SetScript("OnClick"/"OnDragStart"/"OnDragStop"/"OnEnter"/"OnLeave")` | always-on | the chain is the add-on's own button | n/a |
| 32 | `RankBrowser.lua:2289-2296` | `CreateFrame("Frame", "TacoTipRankFrame", g.UIParent, …)` — an ADD-ON frame parented to the Blizzard `UIParent` | frame creation | conditional | n/a | n/a |
| 33 | `RankBrowser.lua:1648`, `:2392` | `CreateFrame("Button", nil, f, "UIPanelCloseButton")` | add-on close button, **Blizzard template** whose `<OnClick function="UIPanelCloseButton_OnClick"/>` is Blizzard Lua | conditional | the chain is the add-on's own button; the handler is Blizzard's | n/a |
| 34 | `Options.lua:1553` | `CreateFrame("Frame", "TacoTip_ExtrasOptionsPanel")` | the add-on's own panel, **no parent** | always-on | n/a | n/a |
| 35 | `Options.lua:647/683/941/1045/1078/1092/1168/1236/1277/1514/1788` | add-on widgets under the add-on panel; three use **Blizzard templates** (`InterfaceOptionsCheckButtonTemplate`, `UIPanelButtonTemplate`) | frame creation | always-on | n/a | n/a |
| 36 | `Core.lua:68`, `:1323`, `:1563`; `Frames.lua:1515-1516`; `RankSync.lua:77`, `:1509-1510`; `TacoTipAdapter.lua:1167`; `Options.lua:1806`, `:1928-1929`; `RankBrowser.lua:2116`, `:2289`… | **ADD-ON-created** event frames | `SetScript("OnEvent"/"OnUpdate"/"OnShow"/"OnHide")` | always-on | the chain is the add-on's own frame | n/a |
| 37 | `Scanner.lua:1055`; `Frames.lua:938`, `:952-953`; `TacoTipAdapter.lua:915-916`, `:951-960`, `:1084`; `Minimap.lua:52-61`, `:81-97`, `:268-281` | `InspectFrame`, `PaperDollFrame`, `CharacterModelFrame`, `CharacterModelScene`, `InspectModelFrame`, `Minimap` | **READ-ONLY** (`GetRect`, `GetLeft/Right/Top/Bottom`, `GetWidth/Height`, `GetCenter`, `GetEffectiveScale`, `GetFrameLevel`, `GetParent`, `.unit`) | always-on | n/a | n/a |

### 1.2 What is NOT in the package

- `Detours:DetourHook` — **0 hits**. VERIFIED. (The carrier audit's carrier was in
  the MAIN add-on's vendored `Libs/`, not here.)
- `Mixin(...)` — **0 hits**. VERIFIED. The Extras never adds a field to a
  Blizzard table, so it can never replace a Blizzard method.
- `rawset` onto a Blizzard global — **0 hits**. VERIFIED.
- `CreateFontString` / `CreateTexture` under a **Blizzard** parent — **0 hits**.
  VERIFIED: every `CreateFontString`/`CreateTexture` in the package is under an
  ADD-ON frame (rows 27, 30). The one add-on object created under a Blizzard
  parent is `TacoTip_ExtrasMinimapButton` (row 29) and the summary `block`
  (row 26); neither creates a region under the Blizzard parent.

### 1.3 The one cross-add-on hook

`TacoTipAdapter.lua:1524-1555` `installEquipmentHook` posts a hook on the
**TacoTip main add-on's** table:

    1541	    local ok, installed = pcall(
    1542	        captured.hookFunction,      -- _G.hooksecurefunc, captured at :812
    1543	        captured.tacoTip,          -- the OTHER add-on's table
    1544	        methodName,                -- "RefreshCharacterFrame" / "RefreshInspectFrame"
    1545	        callback
    1546	    )

This is **not** a Blizzard object. It is a post-hook on the sibling add-on, and
the sibling's `hookFunction` reference is a capability probe
(`TacoTipAdapter.lua:742`, `:812`) whose absence disables the whole
equipment surface (`:758`, `:774-775`). VERIFIED. The body is internally
`pcall`-guarded (`:1529-1538`). Recorded as **F5 (nit)** because the sibling
may call those methods from inside a Blizzard frame's chain, in which case the
Extras' body runs there uncontained.

### 1.4 The `parentKey` / global-name collision question

| add-on global | created at | client collision? |
|---|---|---|
| `TacoTip_ExtrasMinimapButton` | `Minimap.lua:188-192` | **none** |
| `TacoTip_ExtrasOptionsPanel` | `Options.lua:1553` | **none** |
| `TacoTip_ExtrasHelp*` | `Options.lua:647`, `:683` | **none** |
| `TacoTip_ExtrasCharacterSummary` / `…InspectSummary` | `Frames.lua:1290-1294` | **none** |
| `TacoTip_ExtrasCharacterSummaryHandle` / `…InspectSummaryHandle` | `Frames.lua:1312-1317` | **none** |
| `TacoTipRankFrame`, `TacoTipRankClassFilter`, `TacoTipRankScrollFrame`, `TacoTipRankEscFrame` | `RankBrowser.lua:2289`, `:2501`, `:2642`, `:2808` | **none** |

VERIFIED by a whole-tree sweep on all five branches:

    for b in classic_era classic_anniversary classic_titan forever live; do
        git grep -c "TacoTip" origin/$b -- Interface/ | wc -l   # -> 0 on every branch
    done

**No client global on any of the five branches contains the string `TacoTip`.**
No `parentKey` is used anywhere in the package, so no parent-scoped key can
collide. VERIFIED.

---

## 2. A2 — the inspect-frame post-hooks, per branch

`Frames.lua:1418-1430` installs three post-hooks through `safeSecureHook`
(`Frames.lua:1369-1383`), which does `pcall(_G.hooksecurefunc, method, callback)`
(`:1377`) — **a missing global raises inside the pcall and is swallowed**, so a
missing global is a no-op, never a load abort. VERIFIED.

### 2.1 Do the three globals exist? Is it Lua or engine?

**All three are Lua globals on all five branches.** VERIFIED.

| global | classic_era | classic_anniversary | classic_titan | forever | live |
|---|---|---|---|---|---|
| `InspectFrame_Show` | Lua — `Blizzard_InspectUI/Vanilla/Blizzard_InspectUI.lua:3` (and `TBC/…:8`) | same files | same files | Lua — `Blizzard_InspectUI/Mainline/Blizzard_InspectUI.lua:8` (and `Camelot/…:41`) | Lua — `Blizzard_InspectUI/Mainline/Blizzard_InspectUI.lua:8` |
| `InspectFrame_UnitChanged` | Lua — `Vanilla/…:59` (and `TBC/…:73`) | same | same | Lua — `Mainline/…:77` | Lua — `Mainline/…:77` (also `TBC/…:73`, `Vanilla/…:59`) |
| `InspectSwitchTabs` | Lua — `Vanilla/…:88` (and `TBC/…:108`) | same | same | Lua — `Mainline/…:111` (and `Camelot/…:154`) | Lua — `Mainline/…:111` |

Cited form (`origin/classic_era:Interface/AddOns/Blizzard_InspectUI/Vanilla/Blizzard_InspectUI.lua`):

     3	function InspectFrame_Show(unit)
    59	function InspectFrame_UnitChanged(self)
    88	function InspectSwitchTabs(newID)

### 2.2 Where are they called from — and is that a frame's script chain?

**`InspectFrame_Show`** — called from `InspectUnit`, a **plain global function**,
on every branch. VERIFIED:

    origin/classic_era:Interface/AddOns/Blizzard_UIParent/Vanilla/UIParent.lua
     337	function InspectUnit(unit)
     338		InspectFrame_LoadUI();
     339		if ( InspectFrame_Show ) then
     340			InspectFrame_Show(unit);
     341		end
     342	end

    origin/live:Interface/AddOns/Blizzard_InspectUI/Mainline/Blizzard_InspectUI_Bootstrap.lua
      7	function InspectUnit(unit)
      8		if InspectFrame_LoadUI() then
      9			if ( PlayerSpellsFrame and PlayerSpellsFrame:IsInspecting() ) then
     10				HideUIPanel(PlayerSpellsFrame);
     11			end
     12
     13			InspectFrame_Show(unit);
     14		end
     15	end

`InspectUnit` is not a frame script handler, so the `InspectFrame_Show`
post-hook body is **not** inside a Blizzard frame's script chain. (It *is*
inside the call chain of the engine's `Inspect()`.) VERIFIED.

**`InspectSwitchTabs`** — **called from inside a frame's script chain** on every
branch: the inspect tab Button's `<OnClick>`. VERIFIED.

    origin/classic_era:Interface/AddOns/Blizzard_InspectUI/Vanilla/Blizzard_InspectUI.xml
    46			<Button name="InspectFrameTab1" inherits="CharacterFrameTabButtonTemplate" id="1" text="CHARACTER">
    50				<Scripts>
    51					<OnClick function="InspectFrameTab_OnClick"/>

    origin/classic_era:…/Vanilla/Blizzard_InspectUI.lua
    100	function InspectFrameTab_OnClick(self)
    101		PlaySound(SOUNDKIT.IG_CHARACTER_INFO_TAB);
    102		InspectSwitchTabs(self:GetID());
    103	end

    origin/live:Interface/AddOns/Blizzard_InspectUI/Mainline/Blizzard_InspectUI.xml
     6			<Button name="InspectFrameTab1" inherits="PanelTabButtonTemplate" id="1" text="CHARACTER">
    10				<Scripts>
    11					<OnClick function="InspectFrameTab_OnClick"/>

`InspectSwitchTabs` is also called from `InspectFrame_Show` (`:8` / `:14`) and
from `InspectFrame_UpdateTabs` (`:133` / `:150` classic, `:140` mainline) — both
plain functions. The tab-button path is the one that matters: it is a real
Blizzard script chain, and the Extras' post-hook body runs there. **The body is
contained** (`boundedCallback` → `Core.RunUntainted`, `Frames.lua:92`). VERIFIED.

**`InspectFrame_UnitChanged` — DEAD on all five clients.** VERIFIED by a
whole-tree sweep (not a grep of one file):

    for b in classic_era classic_anniversary classic_titan forever live; do
        git grep -n "InspectFrame_UnitChanged" origin/$b ; done

    origin/classic_era:…/Vanilla/Blizzard_InspectUI.lua:59:function InspectFrame_UnitChanged(self)
    origin/classic_era:…/TBC/Blizzard_InspectUI.lua:73:function InspectFrame_UnitChanged(self)
    origin/live:…/Mainline/Blizzard_InspectUI.lua:56:        --	InspectFrame_UnitChanged(self);
    origin/live:…/Mainline/Blizzard_InspectUI.lua:77:function InspectFrame_UnitChanged(self)

**There is not one call site on any branch.** The only non-definition hit is a
**commented-out** call on the mainline pair (`Mainline/Blizzard_InspectUI.lua:56`,
inside the `PLAYER_TARGET_CHANGED` branch of `InspectFrame_OnEvent`). VERIFIED.

Consequence: `Frames.lua:1421-1423` installs a post-hook that **can never fire**
on any of the five clients, and the `bindInspectUnit(true)` refresh it was
meant to trigger never runs from that path.

### 2.3 Are the post-hook bodies contained?

**Yes, all three.** VERIFIED — `Frames.lua:1418`, `:1421`, `:1424` all pass
`boundedCallback(label, fn)`, and `boundedCallback` returns

    Frames.lua:80	    return function(...)
    Frames.lua:92	        return Core.RunUntainted(bounded, ...)

so every post-hook body runs inside `Core.RunUntainted`. VERIFIED.

---

## 3. A3 — the paper-doll / inspect-pane hooks, per branch

### 3.1 The `hidden` attribute (the whole question)

Parsed with a namespace-aware XML parser, per branch:

| frame | classic_era | classic_anniversary | classic_titan | forever | live |
|---|---|---|---|---|---|
| `PaperDollFrame` | **no `hidden`** | **no `hidden`** | **no `hidden`** | **no `hidden`** | **no `hidden`** |
| `InspectPaperDollFrame` | **no `hidden`** | **no `hidden`** | **no `hidden`** | **no `hidden`** | **no `hidden`** |
| `InspectFrame` | `hidden="true"` | `hidden="true"` | `hidden="true"` | `hidden="true"` | `hidden="true"` |

Quoted declarations (identical in shape on every branch):

    origin/classic_era:Interface/AddOns/Blizzard_CharacterFrame/Vanilla/PaperDollFrame.xml:127
     127		<Frame name="PaperDollFrame" setAllPoints="true" enableMouse="true" parent="CharacterFrame" useParentLevel="true" id="1">

    origin/classic_era:Interface/AddOns/Blizzard_InspectUI/Classic/InspectPaperDollFrame.xml:74
      74		<Frame name="InspectPaperDollFrame" setAllPoints="true" useParentLevel="true" parent="InspectFrame" id="1">

    origin/classic_era:Interface/AddOns/Blizzard_InspectUI/Vanilla/Blizzard_InspectUI.xml:3
       3		<Frame name="InspectFrame" toplevel="true" movable="true" enableMouse="true" hidden="true" parent="UIParent" inherits="ButtonFrameTemplate">

    origin/live:Interface/AddOns/Blizzard_InspectUI/Mainline/Blizzard_InspectUI.xml:4
       4	    <Frame name="InspectFrame" toplevel="true" movable="true" enableMouse="true" hidden="true" parent="UIParent" inherits="ButtonFrameTemplate">

    origin/forever:Interface/AddOns/Blizzard_InspectUI/Mainline/Blizzard_InspectUI.xml:3
       3	    <Frame name="InspectFrame" toplevel="true" movable="true" enableMouse="true" hidden="true" parent="UIParent" inherits="ButtonFrameTemplate">

### 3.2 Which hook can EVER fire?

| hook | file:line | can it EVER fire? | evidence |
|---|---|---|---|
| `character.OnShow` | `Frames.lua:1352` | **NO — on all five** | `PaperDollFrame` has no `hidden` attribute → created shown → its `OnShow` fired at creation, before the add-on loaded. **VERIFIED.** |
| `character.OnHide` | `Frames.lua:1353` | **NO — on all five** | `PaperDollFrame` is never hidden or shown by the client: a whole-tree sweep found **no** `PaperDollFrame:Hide()` / `PaperDollFrame:Show()` on any branch. **VERIFIED.** |
| `character.OnSizeChanged` | `Frames.lua:1356` | never observed | `PaperDollFrame` is `setAllPoints="true"` on a fixed-size `CharacterFrame`; the client never resizes it. **ASSUMED** (absence of a resize site). |
| `inspect.OnShow` | `Frames.lua:1401` | **YES — on all five** | `InspectPaperDollFrame` is `INSPECTFRAME_SUBFRAMES[1]`, and `InspectSwitchTabs` does `oldFrame:Hide()` then `newFrame:Show()` on it. On the first inspect, `oldFrame == newFrame == InspectPaperDollFrame` (the selected tab is 1, set in `InspectFrame_OnLoad`), so the frame is hidden and re-shown → `OnShow` fires. **VERIFIED** (`Blizzard_InspectUI.lua:88-98` classic / `:111-121` mainline; `INSPECTFRAME_SUBFRAMES[1] == "InspectPaperDollFrame"` on all five). |
| `inspect.OnHide` | `Frames.lua:1402` | **YES — on all five** | the `oldFrame:Hide()` half of the same `InspectSwitchTabs` body. **VERIFIED.** |
| `inspect.OnSizeChanged` | `Frames.lua:1405` | never observed | `InspectPaperDollFrame` is `setAllPoints="true"` on a fixed-size `InspectFrame`. **ASSUMED.** |
| `inspectFrame.OnShow` | `Frames.lua:1410` | **YES — on all five** | `InspectFrame` carries `hidden="true"` and is shown by `ShowUIPanel(InspectFrame)` (`InspectFrame_OnEvent`, `INSPECT_READY`). **VERIFIED.** |
| `inspectFrame.OnHide` | `Frames.lua:1415` | **YES — on all five** | `InspectFrame` declares `<OnHide function="InspectFrame_OnHide"/>` and `HideUIPanel(InspectFrame)` is called on `PLAYER_TARGET_CHANGED` / `GROUP_ROSTER_UPDATE`. **VERIFIED.** |

### 3.3 The `hidden` attribute of the frames the Extras hooks — the declared `<Scripts>` blocks

| frame | declared scripts (all five branches, identical shape) |
|---|---|
| `PaperDollFrame` | `OnLoad`, `OnEvent`, **`OnShow`**, **`OnHide`** — no `OnSizeChanged` |
| `InspectPaperDollFrame` | `OnLoad`, `OnEvent`, **`OnShow`** — no `OnHide`, no `OnSizeChanged` |
| `InspectFrame` | `OnLoad`, `OnEvent`, **`OnShow`**, **`OnHide`** (+`OnUpdate` on forever/live) |

VERIFIED by parsing each branch's XML. This is the input to the §12
escalation: the *declared* set and the *engine*'s per-type set are not the same
thing, and only the engine can say which one `HookScript` validates against.

### 3.4 Is the dead `character.OnShow` hook harmless?

There is a fallback: `Frames.lua:1363-1365`

    1363	    if frameVisible(host) then
    1364	        onCharacterShow()
    1365	    end

and `Frames.lua:1553` in `ApplySettings`. But `frameVisible` (`Frames.lua:187-202`)
prefers `IsVisible()`, and `PaperDollFrame` is a child of the hidden
`CharacterFrame`, so `IsVisible()` is false while the character pane is closed.
The character summary therefore rides on `renderLocal` (reached through
`Scanner.Subscribe(localPublished)`), not on the hook. **This is a finding, not
a demonstrated player-visible break** — see **F1**. The operator's in-game
observation outranks this reading (`CAIRN.md`).

---

## 4. A4 — the shared GameTooltip surface, per branch

### 4.1 Which scripts the shared `GameTooltip` DECLARES

**classic family** (`classic_era`, `classic_anniversary`, `classic_titan`) —
`origin/classic_era:Interface/AddOns/Blizzard_GameTooltip/Classic/GameTooltip.xml:13-35`:

    13		<GameTooltip name="GameTooltip" frameStrata="TOOLTIP" hidden="true" parent="UIParent" inherits="GameTooltipTemplate">
    14			<Scripts>
    15				<OnLoad>
    ...
    22				<OnTooltipSetUnit function="GameTooltip_OnTooltipSetUnit" />
    23				<OnTooltipSetItem function="GameTooltip_OnTooltipSetItem" />
    24				<OnTooltipSetSpell function="GameTooltip_OnTooltipSetSpell" />
    25				<OnHide>
    26					GameTooltip_OnHide(self);
    ...
    33				<OnUpdate function="GameTooltip_OnUpdate"/>
    34			</Scripts>
    35		</GameTooltip>

→ declares **OnLoad, OnTooltipSetUnit, OnTooltipSetItem, OnTooltipSetSpell,
OnHide, OnUpdate**. **No `OnTooltipCleared`, no `OnShow`.**
(Byte-identical on `classic_anniversary` and `classic_titan` — VERIFIED by
reading the same line range on each branch.)

**mainline** (`forever`, `live`) — the template
`origin/live:Interface/AddOns/Blizzard_GameTooltip/Mainline/GameTooltip.xml:4-37`
plus the instance at `:249-274`:

     4		<GameTooltip name="GameTooltipTemplate" mixin="GameTooltipDataMixin" inherits="SharedTooltipTemplate" virtual="true">
    25			<Scripts>
    26				<OnLoad inherit="prepend" function="GameTooltip_OnLoad"/>
    27				<OnHide function="GameTooltip_OnHide"/>
    28				<OnTooltipSetDefaultAnchor>
    31				<OnTooltipCleared>
    35				<OnEvent method="OnEvent"/>
    36			</Scripts>
    37		</GameTooltip>
   ...
   249		<GameTooltip name="GameTooltip" inherits="GameTooltipTemplate" parent="UIParent">
   269			<Scripts>
   270				<OnLoad method="OnLoad"/>
   271				<OnShow function="GameTooltip_OnShow"/>
   272				<OnUpdate function="GameTooltip_OnUpdate"/>
   273			</Scripts>
   274		</GameTooltip>

→ declares **OnLoad, OnHide, OnTooltipSetDefaultAnchor, OnTooltipCleared,
OnEvent, OnShow, OnUpdate**. **No `OnTooltipSetUnit`, no `OnTooltipSetItem`.**
(Identical line numbers on `forever` — VERIFIED.)

### 4.2 The client-side corroboration (this is the "grep is not proof" case)

The XML is not the only evidence, and the two agree:

    for b in forever live; do
        git grep -c "GameTooltip_OnTooltipSetUnit"  origin/$b -- Interface/   # -> 0 files
        git grep -c "GameTooltip_OnTooltipSetItem"  origin/$b -- Interface/   # -> 0 files
        git grep -c "GameTooltip_OnTooltipSetSpell" origin/$b -- Interface/   # -> 0 files
    done

    classic_era: GameTooltip_OnTooltipSetUnit: 2 files
                 GameTooltip_OnTooltipSetItem: 2 files
                 GameTooltip_OnTooltipSetSpell: 2 files

The classic definitions are
`origin/classic_era:Interface/AddOns/Blizzard_GameTooltip/Classic/GameTooltip.lua:498`
(`function GameTooltip_OnTooltipSetUnit(self)`) and
`Classic/GameTooltip.xml:22`. **On `forever` and `live` the client's own
`OnTooltipSetUnit` / `OnTooltipSetItem` / `OnTooltipSetSpell` handlers do not
exist at all** — VERIFIED by a whole-tree sweep of `Interface/`, and there is
no generated-API-doc entry for them either.

### 4.3 The driver mode per branch

| branch | `OnTooltipSetUnit` declared? | `OnUpdate` declared? | `OnShow` declared? | **Extras driver mode** |
|---|---|---|---|---|
| `classic_era` | **yes** (`:22`) | yes (`:33`) | **no** | **unit-hook** |
| `classic_anniversary` | **yes** (`:22`) | yes (`:33`) | **no** | **unit-hook** |
| `classic_titan` | **yes** (`:22`) | yes (`:33`) | **no** | **unit-hook** |
| `forever` | **no** | yes (`:272`) | yes (`:271`) | **poll** |
| `live` | **no** | yes (`:272`) | yes (`:271`) | **poll** |

`Tooltips.lua:1722` — `driverMode = unitHooked and "unit-hook" or "poll"`.
VERIFIED.

**This conclusion is robust to the one thing the mirror cannot settle.**
`HasScript`'s exact semantics (type-support vs. handler-assigned) are
engine-side, but the driver mode does **not** depend on it, because the
effective gate is the `pcall` around `HookScript`:

    Tooltips.lua:1692	        if declares[script] then
    Tooltips.lua:1693	            local hooked = pcall(
    Tooltips.lua:1694	                tooltip.HookScript, tooltip, script, contained(SCRIPT_HANDLERS[script])
    Tooltips.lua:1695	            )
    Tooltips.lua:1696	            if hooked and script == "OnTooltipSetUnit" then
    Tooltips.lua:1697	                unitHooked = true

Under **either** reading of `HasScript`, `unitHooked` can only become true if
`HookScript` on `OnTooltipSetUnit` actually succeeded — and on `forever`/`live`
the client has no such script on the shared tooltip at all (§4.2), so the
`HookScript` cannot succeed and the mode is **poll**. VERIFIED by construction.

### 4.4 Is the `HasScript` guard present at EVERY install site?

| install site | guard | verdict |
|---|---|---|
| `Tooltips.lua:1693-1695` — the four script hooks | `if declares[script] then` (`:1692`), and `declares` is read once from `tooltip:HasScript(script)` (`:1681`) | **yes** |
| `Tooltips.lua:1706-1708` — the `OnUpdate` poll | `if not declares.OnTooltipSetUnit and declares.OnUpdate then` (`:1705`) | **yes** |
| `Tooltips.lua:1727-1728` — the `OnShow` arm | `if declares.OnShow and pcall(tooltip.HookScript, …)` (`:1727-1728`) | **yes** |
| `Tooltips.lua:1590` — the surface itself | `if type(tooltip) ~= "table" or type(tooltip.HookScript) ~= "function"` | **yes** |

**Every install site is guarded.** VERIFIED.

One note for the record: the classic `GameTooltipTemplate` carries
`mixin="GameTooltipMixin"` (`Blizzard_SharedXML/Classic/GameTooltipTemplate.xml:22`)
and that mixin defines `GameTooltipMixin:OnTooltipCleared()`
(`Blizzard_SharedXML/Classic/GameTooltipTemplate.lua:20`) and
`GameTooltipMixin:OnHide()` (`:8`). So the classic shared tooltip may or may
not carry an `OnTooltipCleared` handler depending on how the engine registers
a mixin member as a script — **UNKNOWN** from the mirror. It changes nothing:
the Extras' behaviour is identical under both answers, because the classic
tooltip's `OnTooltipSetItem` and `OnHide` (both definitely declared) already
route to `onTooltipCleared` (`Tooltips.lua:1636-1638`).

---

## 5. A5 — the minimap button, per branch

### 5.1 Is `Minimap` a Blizzard frame? Is there a `MinimapButton` child?

`Minimap` is a Blizzard frame on all five branches. VERIFIED:

    origin/classic_era:Interface/AddOns/Blizzard_Minimap/Classic/Minimap.xml:89
      89					<Minimap name="Minimap" enableMouse="true">
    origin/forever:Interface/AddOns/Blizzard_Minimap/Mainline/Minimap.xml:195
     195					<Minimap name="Minimap" parentKey="Minimap" mixin="MinimapMixin" enableMouse="true">
    origin/live:Interface/AddOns/Blizzard_Minimap/Mainline/Minimap.xml:178
     178					<Minimap name="Minimap" parentKey="Minimap" mixin="MinimapMixin" enableMouse="true">

**There is NO `MinimapButton` frame and NO `MinimapButton` template on any of
the five branches.** VERIFIED by a whole-tree sweep:

    for b in classic_era classic_anniversary classic_titan forever live; do
        git grep -n "MinimapButton" origin/$b -- Interface/ ; done

The only hits are:
- classic family: the Lua **functions** `MinimapButton_OnMouseDown`
  (`Blizzard_Minimap/Classic/Minimap.lua:234`) and `MinimapButton_OnMouseUp`
  (`:243`) — not frames;
- forever/live: `ExpansionLandingPageMinimapButton` /
  `GarrisonLandingPageMinimapButton` — different globals.

So the brief's premise ("a `MinimapButton` child") is **false on all five
clients**; there is nothing to inherit and nothing to collide with.

### 5.2 Does the add-on's button use the `MinimapButton` template?

**No — and it cannot, because no such template exists.** VERIFIED.
`Minimap.lua:188-192`:

    188	    button = CreateFrame(
    189	        "Button",
    190	        addonName .. "MinimapButton",   -- "TacoTip_ExtrasMinimapButton"
    191	        minimap                          -- parent = the Blizzard Minimap
    192	    )

No template argument. The button is a plain `Button` with three
`CreateTexture` children (`Minimap.lua:206`, `:211`, `:217`) and a
`SetHighlightTexture` (`:222`).

### 5.3 `parentKey` / name collision

- **No `parentKey`** is used. VERIFIED.
- The name is the add-on's OWN global `TacoTip_ExtrasMinimapButton`. **No
  client global on any branch contains the string `TacoTip`** (§1.4). VERIFIED.

### 5.4 `RegisterForClicks` / `RegisterForDrag`

**Both are present**, and the code says why:

    Minimap.lua:203	    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    Minimap.lua:204	    button:RegisterForDrag("LeftButton")

VERIFIED. The comment at `Minimap.lua:199-202` is correct: WoW only delivers
the mouse buttons a frame has registered for, so a LeftButtonUp-only
registration would make the right-click branch of `onClick` unreachable.

### 5.5 One thing to note

`Minimap.lua:149-165` / `:167-172`: the button's own `OnEnter` / `OnLeave`
**mutate the shared `GameTooltip`** (`SetOwner` / `SetText` / `AddLine` /
`Show` / `Hide`). The script chain is the **add-on's own button**, not a
Blizzard frame, so the taint does not land on a Blizzard chain — but it IS a
mutation of the shared tooltip, the very object the carrier audit identified as
the one the game menu's buttons anchor to. Recorded as **F4 (nit)**; the
precedent is `bench/audits/2026-10-21-quit-taint-carrier.md` §10.5 item 1,
which recorded the same shape for the MAIN add-on's options hover.

---

## 6. A6 — the options panel, per branch

### 6.1 Does `InterfaceOptions_AddCategory` exist?

**VERIFIED ABSENT** from the whole `Interface/` tree **and** from the
generated API docs, on all five branches:

    for b in classic_era classic_anniversary classic_titan forever live; do
        git grep -n "InterfaceOptions_AddCategory" origin/$b ;            # -> no hits
        git grep -n '"InterfaceOptions_AddCategory"' origin/$b \
            -- "Interface/AddOns/Blizzard_APIDocumentationGenerated/" ;     # -> no hits
        git grep -n "InterfaceOptions" origin/$b ;                          # -> only
                                                                            #    InterfaceOptionsCheckButtonTemplate
                                                                            #    and InterfaceOptionsBaseCheckButtonTemplate
                                                                            #    (Blizzard_FrameXML/DeprecatedTemplates.xml:34-35)
    done

There is therefore **no API-doc entry to quote** — the identifier does not
exist in the client's FrameXML or in its generated documentation. It is
engine-provided if it exists at all. The Extras only reaches it as a guarded
fallback (`Options.lua:2029-2031` → `if type(add) ~= "function" then return false end`),
and the modern path succeeds first on every client (§6.2), so
`registerLegacyCategory` and `openLegacyCategory` are **dead fallbacks on all
five clients**. VERIFIED, and the code says so (`Options.lua:2088-2091`).

### 6.2 Where does Blizzard parent the panel?

**The engine does, through an attribute delegate.** The whole modern Settings
API is present on all five branches:

    origin/classic_era:Interface/AddOns/Blizzard_Settings_Shared/Blizzard_Settings.lua
     133	function Settings.RegisterAddOnCategory(category)
     143	function Settings.OpenToCategory(categoryID, scrollToElementName)
     161	function Settings.RegisterCanvasLayoutCategory(frame, name)
     165	function Settings.RegisterCanvasLayoutSubcategory(parentCategory, frame, name)

    origin/forever:…/Blizzard_Settings.lua
     134	function Settings.RegisterAddOnCategory(category)
     144	function Settings.OpenToCategory(categoryID, scrollToElementName)
     162	function Settings.RegisterCanvasLayoutCategory(frame, name)
     166	function Settings.RegisterCanvasLayoutSubcategory(parentCategory, frame, name)

and the implementation, per branch:

    origin/classic_era:Interface/AddOns/Blizzard_Settings_Shared/Blizzard_SettingsInbound.lua
     94	function SettingsInbound.RegisterCanvasLayoutCategory(frame, name)
     95		AttributeDelegate:SetAttribute(SettingsInbound.RegisterCanvasLayoutCategoryAttribute, { frame, name, });
     96		return AttributeDelegate:GetSecureAttributeResults();
     97	end

`SettingsInbound.RegisterCanvasLayoutCategoryAttribute =
"register-canvas-layout-category"` (`:69`) — the **engine** receives the
add-on's frame and parents it. The client's own registration example is
`Blizzard_Settings_Shared/Blizzard_ImplementationReadme.lua:11`:

    11	local category, layout = Settings.RegisterCanvasLayoutCategory(myFrame, "My Addon");

The Extras does exactly this (`Options.lua:1994-1998`), and the add-on's
category name is read back from the sibling add-on's own TOC metadata
(`Options.lua:1964-1980`, `tacoTipCategoryName()`), so the nesting under
TacoTip's root is by name, not by assumption. VERIFIED.

### 6.3 Is the panel an add-on frame?

**Yes.** `Options.lua:1553`:

    1553	    panel = CreateFrame("Frame", addonName .. "OptionsPanel")

No parent, no template, no `parentKey`. VERIFIED.

### 6.4 Are the `OnEnter` / `OnLeave` hooks on the add-on's own widgets, or on a Blizzard widget?

**On the add-on's own widgets — every one of them.** VERIFIED: all twelve
`attachHelp` call sites pass an add-on-created object.

| call site | object | kind |
|---|---|---|
| `Options.lua:651` | `region` from `createHelpRegion` (`:646-653`, `CreateFrame("Frame", …, panel)`) | add-on `Frame` |
| `Options.lua:687` | `region` from `createStatusHelpRegion` (`:682-690`) | add-on `Frame` |
| `Options.lua:979` | `check` (`:941`, `CreateFrame("CheckButton", …, panel, "InterfaceOptionsCheckButtonTemplate")`) | add-on `CheckButton` (Blizzard **template**) |
| `Options.lua:1069` | `dropDown` (`:1045`, `CreateFrame("Frame", …, "UIDropDownMenuTemplate")`) | add-on `Frame` |
| `Options.lua:1072` | `dropDownButton` | add-on `Button` |
| `Options.lua:1086` | `region` | add-on `Frame` |
| `Options.lua:1131` | `check` | add-on `CheckButton` |
| `Options.lua:1192` | `dropDown` | add-on `Frame` |
| `Options.lua:1197` | `dropDownButton` | add-on `Button` |
| `Options.lua:1287` | `reset` (`:1277`) | add-on `Button` |
| `Options.lua:1521` | `button` (`:1514`, `CreateFrame("Button", …, panel, "UIPanelButtonTemplate")`) | add-on `Button` (Blizzard **template**) |

**No Blizzard widget is ever hooked.** The `InterfaceOptionsCheckButtonTemplate`
and `UIPanelButtonTemplate` are Blizzard *templates* (both present on all five
branches — VERIFIED), so the template's own handlers stay in the chain; the
add-on only adds its own.

The install path itself (`Options.lua:615-644`):

    626	    local hasScript = type(owner.HasScript) == "function" and owner.HasScript
    627	    local hookedAny = false
    628	    if type(owner.HookScript) == "function"
    629	        and hasScript
    630	        and owner:HasScript("OnEnter")
    631	        and owner:HasScript("OnLeave") then
    632	        local okEnter = pcall(owner.HookScript, owner, "OnEnter", onEnter)
    633	        local okLeave = pcall(owner.HookScript, owner, "OnLeave", onLeave)
    634	        hookedAny = okEnter and okLeave
    635	    end
    636	    if not hookedAny then
    640	        pcall(owner.SetScript, owner, "OnEnter", onEnter)
    641	        pcall(owner.SetScript, owner, "OnLeave", onLeave)
    642	    end

The `HasScript` guard is present and the `SetScript` fallback is `pcall`-wrapped,
so a raise there is swallowed rather than aborting the load. VERIFIED. Whether
a plain `Frame`'s `OnEnter` ever **dispatches** is engine-side and is part of
the §12 escalation.

### 6.5 The options panel's own script chain

`Options.lua:1290-1291`, `:1806`, `:1928-1929` install `SetScript` on the
add-on's **own** `equipmentPanel` / `panel` — not a Blizzard frame. VERIFIED.

---

## 7. A7 — the saved-variable shape (`TacoTipExtrasDB`)

`## SavedVariables: TacoTipExtrasDB` (`TacoTip_Extras.toc:8`). VERIFIED.
`TacoTipExtrasDB` is an **invariant** — this section reports, it does not
propose a change.

### 7.1 The exact shape at first install

`Core.lua:493-540`:

    499	    local persistedRoot = _G.TacoTipExtrasDB
    500	    local freshDatabase = type(persistedRoot) ~= "table"
    501	        or next(persistedRoot) == nil
    ...
    518	    local root = persistedRoot
    519	    if freshDatabase then
    520	        root = {}
    521	        _G.TacoTipExtrasDB = root
    522	    end
    523	    if type(root.settings) ~= "table" then
    524	        root.settings = {}
    525	    end
    526	
    527	    if freshDatabase then
    528	        setEquipmentDisplayDefaults(root.settings)
    529	    elseif root.schema == 1 then
    530	        setEquipmentDisplayDefaults(root.settings)
    531	    elseif root.schema ~= 2
    532	        or type(root.settings.equipmentDisplay) ~= "table" then
    533	        setEquipmentDisplayDefaults(root.settings)
    534	    end
    535	
    536	    root.schema = 2
    537	    normalizeSettings(root.settings)
    538	    database = root
    539	    return root
    540	end

On a **fresh** install (`_G.TacoTipExtrasDB` absent or empty) the table is
built as:

    TacoTipExtrasDB = {
      schema = 2,                                   -- Core.lua:536
      settings = {
        enabled = true,                             -- Core.lua:386
        shamanBlue = true,                          -- Core.lua:392
        tooltip = {
          mode = "Detailed",                        -- Core.lua:117 + :407
          shiftToDetailed = true,                   -- Core.lua:409
          restrictEnhancementMetricsToLevel70 = true,-- Core.lua:410-414
          warningColors = true,                     -- Core.lua:415
          show_server_rank = true,                  -- Core.lua:430
          showServerRank = true,                    -- Core.cpp:431
          fields = {
            gearScore = true, baseGS = false, potentialGS = true,
            delta = true, averageItemLevel = true, completion = true,
          },                                        -- Core.lua:437-442
        },
        minimap = { show = true, angle = 225 },     -- Core.lua:450-458
        equipmentDisplay = {                        -- Core.lua:471-483
          mode = "Detailed", showUnenhanced = false, locked = true,
          characterPosition = nil, inspectPosition = nil,
        },
      },
    }

VERIFIED by reading `Core.lua:255-261` (`setEquipmentDisplayDefaults`),
`:385-491` (`normalizeSettings`) and `:117` (`DEFAULT_TOOLTIP_MODE`).

The `mode` is **not** forced to `"Disabled"` on a fresh install: the
empty-field rule (`Core.lua:161-200`) only fires when **no** field is enabled,
and a fresh install enables five of the six. VERIFIED.

### 7.2 The schema version

**2** (`Core.lua:536`, `root.schema = 2`). The three schema arms are
`freshDatabase` / `schema == 1` / `schema ~= 2 or equipmentDisplay missing`
(`Core.lua:527-534`) — all three call the **same** `setEquipmentDisplayDefaults`
(`:255-261`), which is the deliberate "one set of defaults" refactor the
comment at `:245-254` describes. VERIFIED.

### 7.3 What happens on an old-schema file

- `schema == 1` → `setEquipmentDisplayDefaults(root.settings)` → the three
  equipment values are re-seeded → `root.schema = 2` → `normalizeSettings`
  runs → the file is rewritten as schema 2. VERIFIED.
- `schema` missing or not 2 → same path, **except** that the `elseif` also
  fires when `root.settings.equipmentDisplay` is not a table. VERIFIED.
- `schema > 2` (a FUTURE schema this build does not understand) → a **deep
  copy** is taken and the ORIGINAL is never written:

      503	    futureDatabaseSchema = type(persistedRoot) == "table"
      504	        and type(persistedRoot.schema) == "number"
      505	        and persistedRoot.schema > 2
      507	    if futureDatabaseSchema then
      508	        local runtimeRoot = copyTable(persistedRoot)
      ...
      513	        runtimeRoot.settings.equipmentDisplay.mode = "Disabled"
      514	        database = runtimeRoot
      515	        return runtimeRoot
      516	    end

  The future file is left byte-untouched and the equipment surface is switched
  off so a newer add-on's data is not misread. VERIFIED. This is the behaviour
  `Core.lua:108-111` describes.

### 7.4 Can the add-on WRITE a shape it then fails to read?

**In the shipped path: no.** VERIFIED.

- The normal path mutates `_G.TacoTipExtrasDB` **in place** and then reads the
  same table back (`database = root` at `:538`, `Core.GetSettings()` returns
  `root.settings` at `:542-545`). The shape written is the shape read.
- `normalizeSettings` is total: every write is preceded by a type check
  (`defaultBoolean` at `:202-205` only writes when the current value is not a
  boolean; the `tooltip` / `fields` / `minimap` tables are created if missing
  at `:393-395`, `:432-434`, `:450-452`), and every read of a possibly-absent
  value is guarded. VERIFIED.

**One real edge, recorded as F10 (nit):** on a **future** schema the add-on
operates on a **copy** (`copyTable(persistedRoot)`, `:508`) that is never
written back. Every option the player changes in that session is changed in
memory and then discarded, silently. The behaviour is deliberate and
documented (`Core.lua:108-111`), but it is a write into a table that is never
persisted, and the player gets no message. VERIFIED.

---

## 8. A8 — the whisper path

**The whisper path is still deleted.** VERIFIED by a whole-package sweep
(`Tests/` excluded):

    grep -rni "whisper\|SendChatMessage\|C_ChatInfo\|ChatFrame_\|CHAT_MSG" --include=*.lua .

The hits are:

| file:line | what it is |
|---|---|
| `RankSync.lua:95` | `local cChat = rawget(_G, "C_ChatInfo")` — a capability read |
| `RankSync.lua:105` | `local removeGroup = rawget(g, "ChatFrame_RemoveChannelGroup")` — used to remove the sync channel from the chat-frame channel list |
| `RankSync.lua:308` | `local cChat = rawget(g, "C_ChatInfo")` — the `SendAddonMessage` transport |
| `RankSync.lua:350` | a comment naming `API_C_ChatInfo.SendAddonMessage` |
| `RankSync.lua:1492`, `:1505` | the `CHAT_MSG_ADDON` event and its registration — the **receive** side of the addon-message transport |
| `RankSync.lua:625`, `:695`, `:740`, `:898`, `:1142`, `:1293`, `:1296` | comments stating that there is no whisper path |

**`SendChatMessage` — 0 hits in the whole package.** VERIFIED.
**`C_ChatInfo.SendChatMessage` — 0 hits.** VERIFIED.
**No `WHISPER` chat type is ever sent.** VERIFIED: the only transport is
`C_ChatInfo.SendAddonMessage`, whose chat types are the addon-message
channels (`GUILD`, `PARTY`, `RAID`, …), and the code says so at
`RankSync.lua:688-695`.

The workshop invariant holds. **VERIFIED.**

---

## 9. A9 — locale parity

All eleven `TacoTip_Extras/Locale/*.lua` files were parsed for their key set,
key order and value.

| locale | key count | missing vs enUS | extra vs enUS | duplicate keys | empty values | key ORDER |
|---|---|---|---|---|---|---|
| `enUS` | **154** | — | — | 0 | 0 | baseline |
| `deDE` | **154** | 0 | 0 | 0 | 0 | shared order |
| `esES` | **154** | 0 | 0 | 0 | 0 | shared order |
| `esMX` | **154** | 0 | 0 | 0 | 0 | shared order |
| `frFR` | **154** | 0 | 0 | 0 | 0 | shared order |
| `itIT` | **154** | 0 | 0 | 0 | 0 | shared order |
| `koKR` | **154** | 0 | 0 | 0 | 0 | shared order |
| `ptBR` | **154** | 0 | 0 | 0 | 0 | shared order |
| `ruRU` | **154** | 0 | 0 | 0 | 0 | shared order |
| `zhCN` | **154** | 0 | 0 | 0 | 0 | shared order |
| `zhTW` | **154** | 0 | 0 | 0 | 0 | **differs — 5 positions** |

**Every locale publishes the SAME 154-key set. No key is missing from any
locale; no key exists in only one; no duplicates; no empty values.** VERIFIED.

**Order:** the nine locales `deDE`, `esES`, `esMX`, `frFR`, `itIT`, `koKR`,
`ptBR`, `ruRU`, `zhCN` share **one identical** key order. `zhTW` differs from
that order in **exactly five positions** — the `LB_COL_*` block is rotated by
one:

    idx 111: shared='LB_COL_GS'      zhTW='LB_COL_ILVL'
    idx 112: shared='LB_COL_ILVL'    zhTW='LB_COL_LEVEL'
    idx 113: shared='LB_COL_LEVEL'   zhTW='LB_COL_PLAYER'
    idx 114: shared='LB_COL_PLAYER'  zhTW='LB_COL_LASTSEEN'
    idx 115: shared='LB_COL_LASTSEEN' zhTW='LB_COL_GS'

`enUS` differs from all ten, because it places the thirteen short/awkward keys
(`TIME_UNKNOWN`, `TIME_YESTERDAY`, `GEAR_NO_OPPORTUNITIES`, `LB_COL_SPECCLASS`,
`LB_MY_RANK_ARROW`, `GEAR_SCANNING`, `LB_SORTED_BY`, `LB_FOOTER_NO_RANK`,
`EQUIPMENT_CATEGORY_NAME`, `MINIMAP_HINT_RIGHT`, `COMPLETE`,
`GEAR_UNAVAILABLE`, `LB_FOOTER_STANDING`, `CATEGORY_NAME`) in a different
order than the ten translations do. VERIFIED.

**No functional impact** — the locale table is consumed by key lookup
(`L["KEY"]`), never by position. Recorded as **F7 (nit)**.

**On the "no locale key without a sourced translation" invariant:** the values
that are byte-identical to `enUS` are all brand names, acronyms, format
strings, or words that are genuinely the same in that language — e.g.
`CATEGORY_NAME` ("TacoTip Extras"), `MINIMAP_HINT` ("TacoTip Extras"),
`LB_COL_GS` ("GEARSCORE"), `LB_COL_ILVL` ("iLVL"), `SORT_GS_DESC`
("GEARSCORE"), `LB_TIP_GS` ("GearScore: %d"), `SCAN_PROGRESS` ("%d / %d"), and
`CLASS_PALADIN` in `deDE` / `frFR`. **No locale carries an English sentence
where a translation was required.** VERIFIED. A spot check of `zhTW` confirms
genuine translations (`"TacoTip 裝備分數排行榜"`, `"玩家"`, `"立即掃描"`). VERIFIED.

---

## 10. A10 — the packaging

`TacoTip_Extras/TacoTip_Extras.toc`:

     1	## Interface: 11509, 20506, 38002, 16001, 120105
     2	## Title: |cffd4a84bTacoTip|r |cffbcc3ccExtras|r
     3	## Notes: Optional companion add-on for TacoTip. Requires TacoTip; installs nothing on its own.
     4	## Author: AcidBomb
     5	## X-Curse-Project-ID: 1741092
     6	## Version: 1.2.3
     7	## Dependencies: TacoTip
     8	## SavedVariables: TacoTipExtrasDB
     9	## IconTexture: Interface\AddOns\TacoTip_Extras\tt-2.tga

- **`## Interface` band: all five clients** (11509, 20506, 38002, 16001,
  120105). VERIFIED — every branch the mirror carries is covered.
- **`## Dependencies: TacoTip`** — present. VERIFIED. The Extras is a
  companion; `TacoTipAdapter.lua:65-77` probes TacoTip's table and the whole
  surface is refused when TacoTip is absent (`TacoTipAdapter.lua:754-778`).
- **`## SavedVariables: TacoTipExtrasDB`** — present, and matches the code
  (`Core.lua:499`, `:521`). VERIFIED.
- **File list: 23 runtime files** — 11 `Locale/*.lua` + 12 `.lua`. VERIFIED.

**The release verifier passes:**

    $ bash Tools/verify_release_extras.sh --worktree
    TacoTip Extras release archive — 29 files from the working tree
      (attributes read from the working tree)
    PASS  single .toc: TacoTip_Extras.toc
    PASS  all 23 TOC-listed runtime files are present
    PASS  no .lua outside the TOC's runtime list
    PASS  all 11 Locale/*.lua files are present
    PASS  TOC's ## IconTexture target is present (tt-2.tga)
    PASS  README/CHANGELOG/LICENSE/THIRD_PARTY_NOTICES and the TOC are all present
    PASS  no non-runtime files in the package
    PASS  no Tests/, .luacheckrc, .gitattributes or PNG in the package
    PASS  TacoTip_Extras/.gitattributes declares every non-runtime rule
    verify_release_extras: PASS

**Every file the toc lists exists.** VERIFIED.
**No file that exists in the package but should not ship is in the package.**
The working tree also holds `1.png` … `7.png`, `tt-2.png`, `tt-2.tga`,
`CHANGELOG.md`, `README.md`, `LICENSE`, `THIRD_PARTY_NOTICES.md`,
`.gitattributes`, `.luacheckrc` and `Tests/` — of these, the PNGs, `Tests/`,
`.gitattributes` and `.luacheckrc` are `export-ignore`d and the four documents
plus `tt-2.tga` are deliberately shipped. VERIFIED.

---

## 11. A11 — the containment itself

### 11.0 The three files, quoted

`Core.lua:38-60`:

    38	local secureCallFn = nil
    39	if (type(securecall) == "function") then
    45	    local probeRan = false
    46	    local probeOk = pcall(securecall, function() probeRan = true end)
    47	    if (probeOk and probeRan) then
    48	        secureCallFn = securecall
    49	    end
    50	end
    ...
    55	function Core.RunUntainted(fn, ...)
    56	    if (secureCallFn) then
    57	        return secureCallFn(fn, ...)
    58	    end
    59	    return fn(...)
    60	end

`Frames.lua:70-94`:

    70	local function boundedCallback(label, fn)
    73	    local function bounded(...)
    74	        local ok, err = pcall(fn, ...)
    75	        if not ok then
    76	            hookCallbackErrors = hookCallbackErrors + 1
    77	            lastHookCallbackError = label .. ": " .. tostring(err)
    78	        end
    79	    end
    80	    return function(...)
    ...
    92	        return Core.RunUntainted(bounded, ...)
    93	    end
    94	end

`Tooltips.lua:1653-1673`:

   1653	    local function contained(fn)
   1658	        local function bounded(...)
   1665	            local ok, err = pcall(fn, ...)
   1666	            if not ok then
   1667	                noteRenderError(err)
   1668	            end
   1669	        end
   1670	        return function(...)
   1671	            return Core.RunUntainted(bounded, ...)
   1672	        end
   1673	    end

### 11.1 (a) Does every callback that enters a Blizzard frame's script chain pass through the containment?

**Almost — three named exceptions.** VERIFIED.

| script-chain entry | contained? |
|---|---|
| `Frames.lua:1352/1353/1356` (`PaperDollFrame` OnShow/OnHide/OnSizeChanged) | **yes** |
| `Frames.lua:1401/1402/1405` (`InspectPaperDollFrame` OnShow/OnHide/OnSizeChanged) | **yes** |
| `Frames.lua:1410/1415` (`InspectFrame` OnShow/OnHide) | **yes** |
| `Frames.lua:1418/1421/1424` (the three `hooksecurefunc` post-hook bodies) | **yes** |
| `Tooltips.lua:1693-1695` (the four shared-GameTooltip script hooks) | **yes** |
| `Tooltips.lua:1706-1708` (the `OnUpdate` poll) | **yes** |
| `Tooltips.lua:1727-1728` (the `OnShow` arm) | **yes** |
| **`Tooltips.lua:1746-1760`** (`TooltipDataProcessor.AddTooltipPostCall`) | **NO — F3** |
| **`TacoTipAdapter.lua:1541-1546`** (the post-hook on the sibling add-on's table) | **NO — F5** (not a Blizzard object) |
| **`Options.lua:558-592` / `Minimap.lua:149-165` / `RankBrowser.lua:843-915`** (the shared-GameTooltip **mutations**) | **NO — F4** (the script chain is the add-on's own frame, not a Blizzard one) |

The carrier audit's §5 class ("every addon callback that runs inside a
Blizzard frame's script chain now runs inside `securecall`") is **CONFIRMED
for the Extras** at every one of the seven real script-chain entries.

### 11.2 (b) Is every contained payload's error still REPORTED?

**Yes — the `pcall` is INSIDE the containment at every site.** VERIFIED.

- `Frames.lua:74` — `pcall(fn, ...)` is inside `bounded`, and `bounded` is what
  `Core.RunUntainted` runs. A raise is caught, counted (`hookCallbackErrors`),
  and the last message is kept (`lastHookCallbackError`) and surfaced by
  `/ttgsdebug` (`Frames.GetDebugState`, `Frames.lua:98-103`). VERIFIED.
- `Tooltips.lua:1665` — `pcall(fn, ...)` is inside `bounded`; the raise goes to
  `noteRenderError` (`Tooltips.lua:125-160`), which counts, keeps the last
  message, and hands it to `DEFAULT_CHAT_FRAME:AddMessage` once per distinct
  message. VERIFIED.
- **The fallback path is also correct.** If `securecall` is missing or the
  load-time probe fails (`Core.lua:39-50`), `Core.RunUntainted` calls
  `fn(...)` directly (`Core.lua:59`) — and the `pcall` is STILL inside
  `bounded`, so the error is still reported. VERIFIED. The raise is not
  swallowed by the containment, because the containment never runs a raise: the
  `pcall` is nested **inside** it, not outside. VERIFIED.
- The Extras' render path has a second, independent boundary:
  `renderPlayerTooltip` (`Tooltips.lua:1408-1423`) wraps the body in
  `xpcall(function() … end, noteRenderError)` (`:1413-1415`). VERIFIED.

**This is the exact shape the carrier audit §10.4 demanded, and it is present.**

### 11.3 (c) Is any argument-forwarding wrong?

**No — but one premise is engine-side and needs stating.**

- `Core.RunUntainted(fn, ...)` is a **vararg** function (`Core.lua:55`) and
  forwards `...` to `secureCallFn(fn, ...)` (`:57`). VERIFIED.
- `boundedCallback`'s inner `bounded` is a **vararg** function
  (`Frames.lua:73`) and forwards `...` to `pcall(fn, ...)` (`:74`). The
  OUTER closure is also a vararg function (`:80`) and forwards to
  `Core.RunUntainted(bounded, ...)` (`:92`). VERIFIED.
- `contained`'s inner `bounded` is a **vararg** function (`Tooltips.lua:1658`)
  and forwards `...` to `pcall(fn, ...)` (`:1665`); the outer closure is a
  vararg function (`:1670`) forwarding to `Core.RunUntainted(bounded, ...)`
  (`:1671`). VERIFIED.
- **No `...` appears in a non-vararg function anywhere in the three files.**
  The Lua 5.1 compile-error shape the carrier audit §10.2 records (a plain
  closure using `...`) is **absent**. VERIFIED — and the package loads: the
  harness loads every file on all three interpreters and is 42/42 green, and
  `luacheck` reports 0 errors in 26 files, so there is no syntax error in
  any file.

**The one thing that is NOT provable from the mirror:** whether the engine's
`securecall` forwards a **variable** number of arguments. `securecall` is an
engine global — it is absent from the generated API docs on all five branches
(the only `securecall*` entry in
`Blizzard_APIDocumentationGenerated/FrameScriptDocumentation.lua:379` is
`securecallmethod`), and the FrameXML mirror carries no engine code. Blizzard's
own call sites forward several arguments after the function
(`Blizzard_BuffFrame/BuffFrame.lua:991`
`securecall(self.UpdateDuration, self, self.timeLeft);` — two;
`Blizzard_CommunitiesSecure/CommunitiesAddDialogOutbound.lua:9`
`securecall("GameTooltip_SetBasicTooltip", GameTooltip, text, x, y, wrap);` —
four), which is **strong support** but not proof. **ASSUMED**, and the
harness's mock (`Tests/harness/load_test.lua:1097-1100`) forwards varargs
too, so the mock agrees with the code — the exact "mock agreeing with the code"
shape `hands-up.md` warns about. It is recorded in §12 as a low-risk item:
every contained payload in this package either takes no arguments
(`onTooltipShow`, `onTooltipUpdatePoll` reads the frame from the closure) or
ignores the ones it gets, so a forwarding failure would be silent but
harmless.

---

## 12. The one thing the mirror cannot settle — **escalate before publishing**

### 12.1 The question

**Does `Frame:HookScript(script, handler)` raise when the frame's XML does
not declare that script — or only when the frame's TYPE does not support it?**

This is engine-side. The FrameXML mirror has no engine code, and the
generated API docs do not document `HasScript`/`HookScript` semantics. There
is no `HasScript` entry in `Blizzard_APIDocumentationGenerated/**` on any of
the five branches. VERIFIED.

### 12.2 Why it matters to THIS package

`Frames.lua:1356` and `Frames.lua:1405` hook `OnSizeChanged` on
`PaperDollFrame` / `InspectPaperDollFrame`. **Neither frame declares
`OnSizeChanged` in its XML `<Scripts>` block** (VERIFIED by parsing all five
branches — §3.3). Under the "XML declaration" reading, both hooks raise, the
raise escapes `bindCharacter()` / `bindInspect()` (neither is `pcall`-wrapped
at the call site — `Frames.lua:1521`, `:1536`, `:1484`, `:1487`), and the
character/inspect surface dies on all five clients. Under the "frame type"
reading, `OnSizeChanged` is a base-Frame script and both hooks install.

**The two available pieces of evidence point in opposite directions:**

- **toward "XML declaration"** — the add-on's own operator-witnessed note at
  `Options.lua:594-613`: *"Hooking a help popup onto a widget is where this
  add-on used to abort a load on EVERY supported client… HookScript raises
  'bad argument #2 to HookScript' when the frame does not already declare that
  script."* The same premise is implemented by the harness
  (`Tests/harness/load_test.lua:940-948`, which raises when the mocked frame
  does not declare the script). The abort it fixed was about `OnEnter`/
  `OnLeave` on plain `Frame`s — which is **also** explained by the
  "frame type" reading, because a plain `Frame` may not support
  `OnEnter`/`OnLeave` while a `Button` does. So this evidence does not
  discriminate.
- **toward "frame type"** — Blizzard's own code, VERIFIED on
  `origin/classic_era:Interface/AddOns/Blizzard_SharedXML/Spinner.lua:8`:
  `self:SetScript("OnSizeChanged", self.OnSizeChanged);` on a
  `SpinnerTemplate`, which is a plain `<Frame>` whose `<Scripts>` block
  declares **only** `OnShow` and `OnHide`
  (`Interface/AddOns/Blizzard_SharedXML/Spinner.xml:15-18`). So the engine
  accepts `OnSizeChanged` on a `<Frame>` that does not declare it — i.e. the
  **type** supports it.

**The harness's mock is not decisive either way**: its base-frame script set
is `{OnLoad, OnShow, OnHide, OnEvent, OnUpdate, OnSizeChanged}`
(`Tests/harness/load_test.lua:706-707`) — six scripts, which includes
`OnSizeChanged` and therefore lets the `OnSizeChanged` hook succeed. That
set disagrees with the add-on's own prose at `Options.lua:598-604` (five
scripts, no `OnSizeChanged`). The mock and the prose are inconsistent, and
the mock is the one that is green. **The suite therefore cannot fail on this
point** — the "a pin that cannot fail" shape from `hands-up.md`.

### 12.3 The one-line in-game probe that settles it

    /dump PaperDollFrame:HasScript("OnSizeChanged")

* `true`  → the frame type supports it, the hooks at `Frames.lua:1356`/`:1405`
  install, and the character/inspect surfaces are fine. **Nothing to do.**
* `false` → the frame does not carry the script, and if `HookScript` validates
  the same way the two hooks **raise** → **blocking**. The fix is to drop the
  two `OnSizeChanged` hooks (they reposition a summary block that
  `setRows` already repositions at `Frames.lua:747`) or to guard them with
  `HasScript` the way `Options.lua:626-635` already does for `OnEnter`/`OnLeave`.

Two related probes worth running in the same session:

    /dump PaperDollFrame:HasScript("OnEnter")     -- does a plain Frame support OnEnter?
    /dump GameTooltip:HasScript("OnTooltipSetUnit") -- on live/forever

The first decides whether the **plain-`Frame` help regions** in the options
panel (`Options.lua:646-654`, `:682-690`) can show their help popup at all: on
those the `HasScript` guard at `Options.lua:630-631` is false, so the code
falls back to `SetScript` (`:640-641`), and whether a plain `Frame`'s
`OnEnter` ever **dispatches** is the same engine-side question.

The second is a **belt-and-braces** check only: §4.3 already shows the driver
mode is `poll` on `forever`/`live` under **either** reading, because
`pcall(tooltip.HookScript, …)` is the effective gate. If it returns `true` on
live, the `HasScript` read is type-based and the `pcall` is doing the work —
which is fine, but it should be recorded so the next desk does not have to
re-derive it.

### 12.4 Why this is a "should-fix (verify)", not a "blocking" report

`CAIRN.md`: an absence claim that cannot be verified is ASSUMED and is never
a defect report. This is not an absence claim about a client API — it is a
claim about the engine's script-registration rules, which the mirror cannot
carry. The two available pieces of evidence conflict. The operator's in-game
observation (the top rung) settles it in one command. Reporting it as a
confirmed defect would be exactly the failure the workshop's history records.

**It is also, most likely, already fine**: the Extras ships today, the
`boundedCallback` boundary is the carrier audit's §5 class, and the
`hooksecurefunc` post-hooks are installed and (per §2.2) one of them
(`InspectSwitchTabs`) is exercised every time the player clicks an inspect
tab — which means the boundary code has run in game on at least the classic
family. That is **ASSUMED** for the Extras specifically, because
`bench/audits/2026-10-21-quit-taint-carrier.md` §8.3 records that whether
the operator had the Extras loaded is **UNKNOWN**.

---

## 13. The findings

| id | severity | evidence | finding |
|---|---|---|---|
| **F1** | **should-fix** | **VERIFIED** | `Frames.lua:1352` (`character.OnShow`) and `Frames.lua:1353` (`character.OnHide`) are **dead hooks on all five clients**: `PaperDollFrame` carries no `hidden` attribute (so its `OnShow` fired at creation, before the add-on loaded) and the client never shows or hides it (whole-tree sweep: zero `PaperDollFrame:Hide()`/`:Show()`). The surface rides on `bindCharacter`'s `frameVisible(host)` fallback (`Frames.lua:1363-1365`) and on `ApplySettings` (`Frames.lua:1553`), both of which key off `IsVisible()` — false while `CharacterFrame` is closed. The hook is not the mechanism the code believes it is. |
| **F2** | **should-fix** | **VERIFIED** | `Frames.lua:1421-1423` — the `hooksecurefunc("InspectFrame_UnitChanged", …)` post-hook is **dead on all five clients**: the global has **no call site anywhere in the tree** (only the definitions; the one non-definition hit is a commented-out call at `origin/live` / `origin/forever` `Mainline/Blizzard_InspectUI.lua:56`). The `bindInspectUnit(true)` refresh it was written for never runs from that path. |
| **F3** | **should-fix** | **VERIFIED** (code) / **ASSUMED** (taint consequence) | `Tooltips.lua:1746-1760` — the `TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, fn)` callback is **not** routed through `Core.RunUntainted`. It is a Blizzard-dispatched callback: addon code that runs inside the client's own tooltip data-processing call, with no `securecall` around it. Its raise **is** reported (`renderPlayerTooltip`'s own `xpcall`, `Tooltips.lua:1413-1415`), so this is a taint-containment gap, not a silent-failure gap. |
| **F4** | **nit** | **VERIFIED** | Three surfaces mutate the **shared `GameTooltip`** from an add-on frame's own script chain, with no containment: `Options.lua:558-592` (options help hover), `Minimap.lua:149-165` (minimap-button hover), `RankBrowser.lua:843-915` (leaderboard row hover). The chain is the add-on's own frame, not a Blizzard one, so the taint does not land on a Blizzard script chain — but the shared tooltip is the one object the game menu's buttons anchor to (`bench/audits/2026-10-20-quit-taint.md` §3). Precedent: the carrier audit §10.5 item 1 recorded the same shape for the MAIN add-on. |
| **F5** | **nit** | **VERIFIED** | `TacoTipAdapter.lua:1541-1546` posts a hook on the **sibling add-on's** table (`TacoTip.RefreshCharacterFrame` / `RefreshInspectFrame`), not on a Blizzard object. The body is internally `pcall`-guarded, but it is **not** contained; if the sibling calls those methods from inside a Blizzard frame's chain, the Extras' body runs there uncontained. |
| **F6** | **nit** | **VERIFIED** | `Options.lua:636-642` — the `SetScript("OnEnter"/"OnLeave")` fallback for the **plain-`Frame`** help regions (`Options.lua:646-654`, `:682-690`) is the path those widgets take, because the `HasScript` guard at `:630-631` is false for a plain `Frame` on the "frame type" reading. Whether a plain `Frame`'s `OnEnter` ever dispatches is engine-side — part of §12. |
| **F7** | **nit** | **VERIFIED** | Locale key **order** is not uniform: `zhTW` differs from the other nine translated locales in exactly **5 positions** (the `LB_COL_*` block is rotated by one), and `enUS` differs from all ten. The **key set** is identical (154 in all eleven), so there is no functional impact. |
| **F8** | **nit** | **VERIFIED** | `Options.lua:2028-2044` (`registerLegacyCategory`) and `:2049-2065` (`openLegacyCategory`) are **dead fallbacks on all five clients**: `InterfaceOptions_AddCategory` and `InterfaceOptionsFrame_OpenToCategory` are absent from the whole `Interface/` tree **and** from the generated API docs on every branch, and the modern `Settings.RegisterCanvasLayoutCategory` path succeeds first. The code already says so (`Options.lua:2088-2091`). |
| **F9** | **nit** | **VERIFIED** | `Minimap.lua:188-192` — the add-on's minimap button uses **no template**, because **no `MinimapButton` template exists on any of the five clients** (whole-tree sweep: the only `MinimapButton` identifiers are the classic Lua *functions* `MinimapButton_OnMouseDown`/`_OnMouseUp` and the unrelated `ExpansionLandingPageMinimapButton` / `GarrisonLandingPageMinimapButton`). `RegisterForClicks("LeftButtonUp","RightButtonUp")` and `RegisterForDrag("LeftButton")` are both present (`:203-204`), and the global `TacoTip_ExtrasMinimapButton` collides with nothing (no client global contains the string `TacoTip` on any branch). |
| **F10** | **nit** | **VERIFIED** | `Core.lua:507-516` — on a **future** schema (`schema > 2`) the add-on operates on a **deep copy** (`copyTable`, `:508`) that is never written back, so every option the player changes in that session is silently discarded. Deliberate and documented (`Core.lua:108-111`), but it is a write into a table that is never persisted, with no message. |
| **F12** | **should-fix (verify)** | **UNKNOWN** | `Frames.lua:1356` / `Frames.lua:1405` — the `OnSizeChanged` hooks on `PaperDollFrame` / `InspectPaperDollFrame`, neither of which declares `OnSizeChanged` in its XML. Whether `HookScript` raises is engine-side and the two available pieces of evidence conflict (§12). **One in-game command settles it.** |

---

## 14. Validation bar

| # | requirement | result |
|---|---|---|
| 1 | `git -C /home/sam/wow-ui-source status --porcelain` unchanged by this work | **UNCHANGED** — identical to the pre-work baseline (`?? .vscode/`, `?? SKILL.md`, `?? reference/`). No write, no checkout, no fetch, no commit in the mirror; every read was `git show` / `git grep` / `git ls-tree`. |
| 2 | `git -C /home/sam/TacoTip-Gearscore-TBC status --short` shows **no change to any product file** — only the desk and the one bench artifact | **CONFIRMED by diff against the pre-work baseline.** The tree was ALREADY dirty before this lane (many modified product files from earlier lanes). The before/after diff shows **four** new untracked entries: **two are mine** — `?? desks/extras-publish-review-2026-10-21/` and `?? bench/audits/2026-10-21-extras-publish-review.md` — and **two belong to concurrent lanes that were running while this one worked**: `?? bench/audits/2026-10-21-publish-gate-verification.md` (desk `quit-taint-fix`, mtime 10:24:22) and `?? desks/main-publish-sweep-2026-10-21/` (mtime 10:16:15). Neither was created or touched by this lane. **Zero** product-file changes: the diff of the before/after status filtered to `TacoTip_Extras/*.lua`, `main.lua`, `options.lua`, `gearscore.lua`, `pawn.lua`, `textures.lua` and `Locale/` is **empty**. |
| 3 | Every `path:line` cited came from a command run in this lane, with the output quoted for load-bearing claims | **CONFIRMED.** Every path:line in this artifact comes from a `sed -n`/`grep -n`/`git show`/`git grep`/XML-parse run in this lane; the load-bearing client claims carry the quoted output inline. The §12 item is the one place where a claim is explicitly NOT established, and it says so. |
| 4 | Every client claim names its branch and carries an evidence label | **CONFIRMED.** Every table in §2–§6 has one column per branch; every finding row carries VERIFIED / ASSUMED / UNKNOWN. |

### The suites and the packager, run in this lane

    $ bash TacoTip_Extras/Tests/harness/run_all.sh
    TOTAL 42 invocations: 42 passed, 0 failed          (lua 5.1 / lua 5.4 / luajit)

    $ luacheck TacoTip_Extras
    Total: 0 warnings / 0 errors in 26 files

    $ bash Tools/verify_release_extras.sh --worktree
    verify_release_extras: PASS

---

## 15. What this review could NOT establish

1. **`Frame:HasScript` / `Frame:HookScript` validation semantics** — engine-side.
   Two conflicting pieces of evidence (§12). **UNKNOWN.** Settled by
   `/dump PaperDollFrame:HasScript("OnSizeChanged")`.
2. **Whether the engine's `securecall` forwards a variable number of
   arguments.** Engine-side; the mirror carries no engine code and the
   generated API docs do not carry `securecall` (only `securecallmethod`).
   Blizzard's own multi-argument call sites are strong support. **ASSUMED.**
   Consequence if wrong: silent, and harmless in this package.
3. **Whether the taint-propagation rule itself is as the workshop describes.**
   Engine-side; unchanged from the carrier audit §8.1. **ASSUMED.**
4. **Whether the Extras' own behaviour has been observed in game by the
   operator.** `bench/audits/2026-10-21-quit-taint-carrier.md` §8.3 records
   this as **UNKNOWN**; nothing in this review changes that. Every "the player
   sees X" claim below the XML is therefore a claim about the mirror.
5. **Whether a plain `Frame`'s `OnEnter` / `OnLeave` ever dispatch** — the
   same engine-side question as (1). **UNKNOWN.**
6. **Whether the classic shared `GameTooltip` carries an `OnTooltipCleared`
   handler** through the `GameTooltipMixin` mixin member
   (`Blizzard_SharedXML/Classic/GameTooltipTemplate.lua:20`). **UNKNOWN**; the
   Extras behaves identically either way (§4.4).
7. **Whether `classic_era` and `classic_anniversary` behave alike.** Their
   `Blizzard_GameTooltip/Classic/GameTooltip.xml` and
   `Blizzard_InspectUI/*` files are byte-identical (line endings only), which
   is a fact about the FILES, not proof that the two clients behave alike.
   **UNKNOWN.**
8. **The taint consequence of the `TooltipDataProcessor` post-call** (F3) —
   the code fact is VERIFIED, the taint consequence is engine-side. **ASSUMED.**

---

## 16. One-line answers

- **A1** — 37 Blizzard-object interactions enumerated in §1.1; **no** detour,
  **no** `Mixin`, **no** `rawset` onto a Blizzard global, **no** region created
  under a Blizzard parent. The only Blizzard *script-chain* entries are the
  seven `HookScript` sites in `Frames.lua` / `Tooltips.lua` and the three
  `hooksecurefunc` post-hook bodies, and **all seven `HookScript` sites are
  contained**; three named gaps are F3, F4 and F5.
- **A2** — all three globals are **Lua** on all five branches; `InspectSwitchTabs`
  **is** called from a frame's script chain (the tab Button's `OnClick`);
  `InspectFrame_Show` is not; `InspectFrame_UnitChanged` is **never called at
  all**; all three post-hook bodies are contained.
- **A3** — `InspectFrame` is `hidden="true"` on all five (its hooks fire);
  `PaperDollFrame` and `InspectPaperDollFrame` carry **no** `hidden` attribute
  on any branch. `character.OnShow` and `character.OnHide` can **never** fire;
  `inspect.OnShow` / `inspect.OnHide` **can** fire (via `InspectSwitchTabs`'s
  hide-then-show); `inspectFrame.OnShow` / `OnHide` **can** fire.
- **A4** — classic declares `OnTooltipSetUnit`/`OnTooltipSetItem`/`OnTooltipSetSpell`/
  `OnHide`/`OnUpdate`; mainline declares `OnShow`/`OnUpdate`/`OnHide`/
  `OnTooltipCleared`/`OnEvent`/`OnLoad`/`OnTooltipSetDefaultAnchor` and **no**
  `OnTooltipSetUnit`/`OnTooltipSetItem`. Driver mode: **unit-hook** on the
  classic family, **poll** on forever and live. The `HasScript` guard is
  present at **every** install site.
- **A5** — `Minimap` is a Blizzard frame on all five; there is **no**
  `MinimapButton` child and **no** `MinimapButton` template on any branch; the
  add-on's button uses **no** template, is named `TacoTip_ExtrasMinimapButton`
  (no `parentKey`, no collision), and has **both** `RegisterForClicks` and
  `RegisterForDrag`.
- **A6** — `InterfaceOptions_AddCategory` is **absent** from the whole tree and
  the generated API docs on all five branches (there is no API-doc entry to
  quote); the panel is parented by the **engine** through
  `AttributeDelegate:SetAttribute("register-canvas-layout-category", { frame, name })`;
  the panel is an **add-on** frame; the `OnEnter`/`OnLeave` hooks are on the
  add-on's **own** widgets — **no Blizzard widget is ever hooked**.
- **A7** — schema **2**; first-install shape written by `normalizeSettings`
  (§7.1); `schema == 1` and a missing `equipmentDisplay` both re-seed the same
  three values; `schema > 2` is treated as a future schema and the file is
  left untouched; the shipped path **cannot** write a shape it then fails to
  read (F10 is the one edge).
- **A8** — the whisper path is **still deleted**: no `SendChatMessage`, no
  whisper chat type, no `C_ChatInfo.SendChatMessage` anywhere in the package.
  The only transport is `C_ChatInfo.SendAddonMessage` and the
  `CHAT_MSG_ADDON` event.
- **A9** — **154 keys in every one of the 11 locales**, the same set, no
  missing, no extra, no duplicate, no empty. The key **order** is uniform for
  nine locales and differs for `zhTW` (5 positions) and `enUS` (F7).
- **A10** — the `.toc` declares all five interface versions,
  `## Dependencies: TacoTip` and `## SavedVariables: TacoTipExtrasDB`, and lists
  23 runtime files that all exist; the release verifier **PASSES** with no
  stray file in the package.
- **A11** — (a) **No**: three named exceptions (F3, F4, F5), of which only F3
  is a real Blizzard-dispatched callback. (b) **Yes**: the `pcall` is inside
  the containment at every site, and the no-`securecall` fallback still
  reports. (c) **No**: every `...` is inside a vararg function; there is no
  Lua 5.1 compile-error shape in the package.
