# Cross-client taint surfaces: the globals the game menu touches, and the globals the shipped tree replaces

- **desk:** `taint-crossclient-2026-10-21` · **date:** 2026-10-21 · **run_id:** `taintcrossclient20261021`
- **kind:** client-source verification (READ-ONLY). **No product file was edited.** This lane produced no
  product change and proposes none.
- **supersedes:** nothing on the bench. It **completes** `bench/audits/2026-10-21-quit-taint-carrier.md`
  (which established the carrier on one client) and **corrects one standing claim** in
  `bench/audits/2026-10-20-quit-taint.md` (see §11).
- **evidence labels:** VERIFIED / ASSUMED / UNKNOWN, per `CAIRN.md`.
- **method:** `git -C /home/sam/wow-ui-source show origin/<branch>:<path>`,
  `git -C /home/sam/wow-ui-source ls-tree -r --name-only origin/<branch>`,
  `git -C /home/sam/wow-ui-source grep -n <pattern> origin/<branch> -- <path>` (read-only), plus grep/read of
  this repo's shipped tree. No web. No state-changing git.
- **branches, reported separately throughout:** `classic_era` (11509), `classic_anniversary` (20506),
  `classic_titan` (38002), `forever` (16001), `live` (120105).
- **reading rule used here:** two branches that ship the same FILE are still two clients. Where the mirror
  gives byte-identical files the text says so explicitly and names both branches; where the mirror cannot
  tell two branches apart, §10 says exactly that.

---

## 1. Scope and the one rule under test

The standing rule from `bench/audits/2026-10-21-quit-taint-carrier.md`:

> **a global the game menu calls must never be replaced by an add-on.**

This artifact answers, per branch:

1. which Blizzard globals the shipped tree replaces or wraps (Q1),
2. which globals the game menu's own call graph touches, and whether the tree touches any of them (Q2),
3. whether a global named `GameTooltipStatusBar` exists (Q3),
4. the backdrop API surface of the shared `GameTooltip` (Q4, Q11),
5. `InspectGuildFrame_Update` (Q5, Q12),
6. `StaticPopupDialogs` (Q6),
7. the `securecall` containment API (Q7, Q10),
8. the shared `GameTooltip`'s declared script set (Q8),
9. `GetGameMessageInfo` callers (Q9).

**No product change is proposed here.** This is client truth only.

---

## 2. Q1 — the global inventory: every Blizzard global the shipped tree replaces or wraps

Read from the repo's source, not from any audit. Shipped files confirmed against `TacoTip.toc`
(lines 11-32) and `TacoTip_Extras/TacoTip_Extras.toc`. `OLD/` and `Tests/` are not shipped and were
excluded.

### 2.1 Blizzard GLOBALS replaced — `rawset(_G, ...)`

| # | global | file:line (ours) | mechanism | installed when |
|---|---|---|---|---|
| 1 | `GetGameMessageInfo` | `Libs/LibForeverInspector/LibForeverInspector.lua:5042` | `Detours:DetourHook(lib, "GetGameMessageInfo", inspectGameMessageInfoSink)` → `Libs/LibDetours-1.0/LibDetours-1.0.lua:134 rawset(_G, funcName, func)` | **CONDITIONAL** — `isClassic` only (`LibForeverInspector.lua:5022`, flag defined `:177`) **and** `type(_G.GetGameMessageInfo)=="function"` (`:5041`) |
| 2 | `PlayVocalErrorSoundID` | `Libs/LibForeverInspector/LibForeverInspector.lua:5035` | same detour mechanism | **CONDITIONAL** — `isClassic` only (`:5022`) **and** `type(_G.PlayVocalErrorSoundID)=="function"` (`:5034`) |
| 3 | `InspectGuildFrame_Update` | `main.lua:4087` | `rawset(_G, "InspectGuildFrame_Update", function(...) ... end)` | **CONDITIONAL** — only when `type(rawget(_G,"InspectGuildFrame_Update"))=="function"` (`:4083-4084`) and the guard is not already installed (`:4085`); called from `main.lua:4110` |
| 4 | `SlashCmdList` | `options.lua:700`, `gearscore.lua:226` | `rawset(_G, "SlashCmdList", slashCmdList)` | **FALLBACK ONLY** — runs only when `rawget(_G,"SlashCmdList")` is nil (`options.lua:697-698`) |

**Per-branch reach of these four, given the guards above:**

- `GetGameMessageInfo` — replaced **only on classic_era**. The guard `isClassic` is
  `WOW_PROJECT_CLASSIC ~= nil and WOW_PROJECT_ID == WOW_PROJECT_CLASSIC`
  (`LibForeverInspector.lua:177`) — that is the Classic Era project constant. On classic_anniversary,
  classic_titan, forever and live the guard is false, so the detour is never installed.
  **classic_anniversary: not replaced. classic_titan: not replaced. forever: not replaced. live: not replaced.**
- `PlayVocalErrorSoundID` — **classic_era: replaced. classic_anniversary: not replaced.
  classic_titan: not replaced. forever: not replaced. live: not replaced.** (same `isClassic` guard)
- `InspectGuildFrame_Update` — see §5 / Q12 for the per-branch answer. **classic_era: not replaced
  (the global does not exist there). classic_anniversary: not replaced. classic_titan: not replaced.
  forever: REPLACED. live: REPLACED.**
- `SlashCmdList` — the fallback fires only if the client has no `SlashCmdList` global. The client
  defines it on every branch (`ChatFrameSetup.lua`), so the fallback is inert on
  **classic_era, classic_anniversary, classic_titan, forever and live** — but that is an
  ASSUMED statement about the client's load order until the `SlashCmdList` definition is read per
  branch; the repo-side fact (VERIFIED) is only that the write is guarded by
  `rawget(_G,"SlashCmdList") == nil`.

### 2.2 Blizzard TABLE FIELDS replaced (not `_G` entries, but Blizzard-owned objects)

| global/table | field | file:line (ours) | mechanism | installed when |
|---|---|---|---|---|
| `UIErrorsFrame` | `AddMessage` | `Libs/LibForeverInspector/LibForeverInspector.lua:5027` | `Detours:DetourHook(lib, errors, "AddMessage", inspectErrorSink)` → `LibDetours:123 funcTable[funcName] = func` | **CONDITIONAL** — `isClassic` only (`:5022`) |
| `C_Sound` | `PlayVocalErrorSound` | `Libs/LibForeverInspector/LibForeverInspector.lua:5030` | same table-detour mechanism | **CONDITIONAL** — `isClassic` only (`:5022`) |

**Per branch:** classic_era: both replaced. classic_anniversary: neither. classic_titan: neither.
forever: neither. live: neither.

### 2.3 `Mixin` — ADDS fields, never replaces

| file:line (ours) | what | installed when |
|---|---|---|
| `main.lua:568` `Mixin(_G.GameTooltip, _G.BackdropTemplateMixin)` | grafts `SetBackdrop`/`SetBackdropColor`/… onto the shared `GameTooltip` **frame object** | **CONDITIONAL** — requires `GameTooltip` to exist **AND no `NineSlice`** **AND `_G.BackdropTemplateMixin`** **AND no `GameTooltip.SetBackdrop`** (`main.lua:563-566`) |
| `main.lua:1090` `Mixin(tooltip, BackdropTemplateMixin)` | same, per tooltip | **CONDITIONAL** — `not tooltip.SetBackdrop` and `BackdropTemplateMixin` and `Mixin` present (`main.lua:1089`) |

`Mixin` is `Blizzard_Mixin`-style: it copies fields onto the target. It does **not** replace a global
and does **not** remove anything. §4 shows the guard at `main.lua:563-566` **does not fire on any
branch**.

### 2.4 `hooksecurefunc` — does NOT replace anything

| file:line (ours) | target | form |
|---|---|---|
| `main.lua:3726` | `"GameTooltip_SetDefaultAnchor"` | global-name form (post-hook) |
| `main.lua:4901` | `GameTooltip.FadeOut` (via `Detours:SecureHook` → `LibDetours:73 hooksecurefunc(funcTable, funcName, ...)`) | table/method form (post-hook) |
| `options.lua:568` | `GameTooltip.FadeOut` (same) | table/method form (post-hook) |
| `TacoTip_Extras/Frames.lua:1375`, `:1377` | `InspectFrame_Show`, `InspectFrame_UnitChanged`, `InspectSwitchTabs` (via `safeSecureHook`) | global-name form (post-hook) |

`hooksecurefunc` preserves the identity of the hooked function. The add-on's **body** still runs as
addon code inside the caller's chain — that is a taint question, not a replacement question, and it is
why the tree wraps those bodies in `securecall` (`main.lua:517-525`, `options.lua:39`).

### 2.5 Blizzard-table WRITES that are not global replacements

| file:line (ours) | write | note |
|---|---|---|
| `main.lua:5154` | `rawset(StaticPopupDialogs, "_TacoTipDragButtonConfirm_", {...})` | adds ONE new key; does not replace the table and does not touch any existing key |
| `options.lua:713`, `gearscore.lua:240` | `rawset(slashCmdList, "TACOTIP", function(msg) ... end)` | adds ONE key to the `SlashCmdList` table |

### 2.6 Nothing else replaces a Blizzard global — VERIFIED

Every `_G.NAME =` assignment in the shipped tree writes an **addon-owned** name:
`TacoTip` (`main.lua:15`, `options.lua:117`, `gearscore.lua:20`, `textures.lua:5`), `TT_GS`
(`gearscore.lua:339`), `TACOTIP_LOCALES` / `TACOTIP_LOCALE` / `TACOTIP_ACTIVE_LOCALE`
(`Locale/*.lua`), `TacoTipExtrasDB` (`TacoTip_Extras/Core.lua:521`), `TACOEXTRAS_LOCALES` /
`TACOEXTRAS_LOCALE` (`TacoTip_Extras/Locale/*.lua`), `SLASH_TACOTIPRANKS1..7`
(`TacoTip_Extras/RankBrowser.lua:2992-3014`), `SLASH_TTEXTRAS1` (`TacoTip_Extras/Options.lua:1950`),
`SLASH_TTEXTRASDEBUG1` (`TacoTip_Extras/Core.lua:1296`), `TacoTipExtrasPrintDebugSnapshot`
(`TacoTip_Extras/Core.lua:1279`), `TacoTipExtrasToggleLeaderboard`
(`TacoTip_Extras/RankBrowser.lua:3038`), `_tacoTipInspectGuildGuarded` (`main.lua:4086`).
The only file-scope global functions are `TacoTip_GSCallback` (`main.lua:1731`) and
`TacoTip_CustomPosEnable` (`main.lua:5094`). Every other file-scope assignment found
(`scheduleItemTooltipRefresh`, `optionsFrame`, `openOptionsPanel`, `modernGetConfig`,
`recordOptionsRegFailure`, `renderRemote`, `printOptionsLine`, `captureRemoteBody`,
`resolveTacoTipAddonName`, `resolveTacoTipTable`, `releaseEquipmentLease`, `acquireEquipmentLease`,
`handleEquipmentLifecycle`, `invokeEquipmentRefresh`, `processEquipmentDeferred`) is a forward-declared
`local` (e.g. `main.lua:2028`, `options.lua:50`, `:676`, `:677`, `:1162`,
`TacoTip_Extras/Frames.lua:983`, `TacoTip_Extras/Options.lua:61`, `TacoTip_Extras/Scanner.lua:1098`,
`TacoTip_Extras/TacoTipAdapter.lua:166-168`, `:187-188`, `:663-664`).

**`Libs/LibDBIcon-1.0/` and `Libs/LibDataBroker-1.1/` are in the repo but in no `.toc`** — they are not
part of the shipped tree and are excluded from this inventory.

---

## 3. Q2 — the game menu's own call graph, per branch

Files read per branch: `Blizzard_GameMenu/Shared/GameMenuFrame.lua`,
`Blizzard_GameMenu/Shared/GameMenuFrame.xml`, `Blizzard_SharedXML/Shared/Frame/MainMenuFrameTemplates.lua`,
`Blizzard_SharedXML/{Classic,Mainline}/Frame/MainMenuFrameTemplates.xml`, plus the per-branch
`Blizzard_GameMenu.toc` / `Blizzard_GameMenu_Mainline.toc` / `Blizzard_GameMenu_WoWLabs.toc`.

### 3.1 The Logout/Quit closure

**classic_era** — `Interface/AddOns/Blizzard_GameMenu/Shared/GameMenuFrame.lua:65-71`:

```lua
65      local function GenerateMenuCallback(callback, customSoundEffect)
66          return function()
67              PlaySound(customSoundEffect or SOUNDKIT.IG_MAINMENU_OPTION);
68              HideUIPanel(self);
69              callback();
70          end;
71      end
```

Logout button at `:158`, Quit button at `:159`.

**classic_anniversary** — same path, same lines, read separately on this branch: `:65-71`,
`PlaySound` `:67`, `HideUIPanel(self)` `:68`, `callback()` `:69`; Logout `:158`, Quit `:159`.

**classic_titan** — `GameMenuFrame.lua:93-99`:

```lua
93      local function GenerateMenuCallback(callback, customSoundEffect)
94          return function()
95              PlaySound(customSoundEffect or SOUNDKIT.IG_MAINMENU_OPTION);
96              HideUIPanel(self);
97              callback();
98          end;
99      end
```

Logout button at `:186`, Quit button at `:187`.

**forever** — `GameMenuFrame.lua:164-170`:

```lua
164     local function GenerateMenuCallback(callback, customSoundEffect)
165         return function()
166             PlaySound(customSoundEffect or SOUNDKIT.IG_MAINMENU_OPTION);
167             HideUIPanel(self);
168             callback();
169         end;
170     end
```

Logout button at `:263`, Quit button at `:264`.

**live** — `GameMenuFrame.lua:116-122`:

```lua
116     local function GenerateMenuCallback(callback, customSoundEffect)
117         return function()
118             PlaySound(customSoundEffect or SOUNDKIT.IG_MAINMENU_OPTION);
119             HideUIPanel(self);
120             callback();
121         end;
122     end
```

Logout button at `:215`, Quit button at `:216`.

### 3.2 The complete set of globals the game menu path touches

`GameMenuFrameMixin:OnShow` / `:OnHide` / `:OnEvent` / `:InitButtons`,
`MainMenuFrameMixin:AddButton` / `:AddSection` / `:AddCloseButton` / `:Reset` / `:OnLoad`, and the
`GameMenuFrame.xml` `<Scripts>` block.

| global | classic_era | classic_anniversary | classic_titan | forever | live | replaced by our tree? |
|---|---|---|---|---|---|---|
| `PlaySound` | `GameMenuFrame.lua:67`; `MainMenuFrameTemplates.lua:68` | `:67`; `MainMenuFrameTemplates.lua:68` | `:95`; `MainMenuFrameTemplates.lua:68` | `:166`; `MainMenuFrameTemplates.lua:81` | `:118`; `MainMenuFrameTemplates.lua:76` | **NO** |
| `HideUIPanel` | `GameMenuFrame.lua:68` | `:68` | `:96` | `:167` | `:119` | **NO** |
| `ShowUIPanel` | `GameMenuFrame.lua:52`, `:58`, `:126`, `:134`, `:146` | same | same | same | same | **NO** |
| `Logout` (engine) | `GameMenuFrame.lua:158` | `:158` | `:186` | `:263` | `:215` | **NO** |
| `Quit` (engine) | `GameMenuFrame.lua:159` | `:159` | `:187` | `:264` | `:216` | **NO** |
| `StaticPopup_Visible` | `GameMenuFrame.lua:157` | `:157` | `:185` | `:262` | `:214` | **NO** |
| `StaticPopup_Show` | — | — | `GameMenuFrame.lua:87` | `:123` | `:110` | **NO** |
| `StaticPopupDialogs` | — | — | `GameMenuFrame.lua:6` (WRITE) | `:6` (WRITE) | `:6` (WRITE) | **NO** (we ADD one key, `main.lua:5154`) |
| `CallbackRegistrantMixin` | `GameMenuFrame.lua:19`, `:35` | same | same | same | same | **NO** |
| `FrameUtil` | `GameMenuFrame.lua:21`, `:37` | same | same | same | same | **NO** |
| `EventRegistry` | `GameMenuFrame.lua:14-15`, `:31` | same | same | same | same | **NO** |
| `UpdateMicroButtons` | `GameMenuFrame.lua:23`, `:39` | same | same | same | same | **NO** |
| `CanAutoSetGamePadCursorControl` | `GameMenuFrame.lua:25`, `:41` | same | same | same | same | **NO** |
| `SetGamePadCursorControl` | `GameMenuFrame.lua:26`, `:42` | same | same | same | same | **NO** |
| `GenerateFlatClosure` | `GameMenuFrame.lua:88`, `:103`, `:126`, `:130`, `:134`, `:146`, `:149` | same | same | same | same | **NO** |
| `Kiosk` | `GameMenuFrame.lua:86` | same | same | same | same | **NO** |
| `GetAppropriateTooltip` | `MainMenuFrameTemplates.lua:39`, `:47` | same | same | same | same | **NO** |
| `GameTooltip_AddErrorLine` | `MainMenuFrameTemplates.lua:42` | same | same | same | same | **NO** |
| `CreateFramePool` | `MainMenuFrameTemplates.lua:14` | same | same | same | same | **NO** |
| `Pool_HideAndClearAnchors` | `MainMenuFrameTemplates.lua:5` | same | same | same | same | **NO** |
| `SOUNDKIT` | `GameMenuFrame.lua:67`, `:158`, `:159` | same | same | same | same | **NO** |
| `SettingsPanel` | `GameMenuFrame.lua:88` | same | same | same | same | **NO** |
| `ToggleStoreUI`, `ShowMacroFrame`, `ToggleHelpFrame`, `RatingMenuFrame`, `AddonList`, `EditModeManagerFrame`, `AccountStoreFrame`, `AccountStoreUtil`, `GameRulesUtil` | `GameMenuFrame.lua:103`,`:112-118`,`:124`,`:133`,`:144`,`:149`,`:152` | same | same | same | same | **NO** |
| `C_AddOns`, `C_CatalogShop`, `C_ExternalEventURL`, `C_GameRules`, `C_SplashScreen`, `C_StorePublic` | `GameMenuFrame.lua:74`,`:97`,`:98`,`:115`,`:125`,`:129`,`:151` | same | same | same | same | **NO** |
| `CurrentVersionHasNewUnseenSettings` | `GameMenuFrame.lua:90` | same | same | same | same | **NO** |
| `GameMenuFrameMixin`, `MainMenuFrameMixin` (globals) | `GameMenuFrame.lua:4`, `MainMenuFrameTemplates.lua:2` | same | same | same | same | **NO** |
| `G_GameMenuFrameContextKey` | `GameMenuFrame.lua:2` | same | same | same | same | **NO** |
| `GameTooltip` (frame object, reached via `GetAppropriateTooltip`) | `MainMenuFrameTemplates.lua:39-43`, `:47` | same | same | same | same | **NO** — we only ADD fields (`Mixin`) and post-hook scripts |
| `GameTooltip_SetDefaultAnchor` | reached by the tooltip's own `OnTooltipSetDefaultAnchor` script, not by the game menu | same | same | same | same | **NO** — `hooksecurefunc` post-hook only (`main.lua:3726`) |
| `LayoutMixin` | — | — | — | `GameMenuFrame.lua:73` | `GameMenuFrame.lua:70` | **NO** |
| `NarrationUtil` | — | — | — | `GameMenuFrame.lua:75` | `GameMenuFrame.lua:70` | **NO** |
| `InputUtil` | — | — | — | `GameMenuFrame.lua:87`, `:97` | `GameMenuFrame.lua:87`, `:97` | **NO** |
| `GameMenuEscPriority`, `RegisterGameMenuEscHandler` | — | — | — | `GameMenuFrame.lua:36` | `GameMenuFrame.lua:36` | **NO** |
| `GameMenuFrame_EscapePressed`, `GameMenuFrame_Show` | — | — | — | `GameMenuFrame.lua:26-41` | `GameMenuFrame.lua:26-41` | **NO** |

**Extra `PlaySound` call sites on the game menu path (beyond the closure):**

- classic_era: `MainMenuFrameTemplates.lua:68 PlaySound(SOUNDKIT.IG_MAINMENU_CONTINUE);` (the "Return to
  Game" close button, `AddCloseButton`).
- classic_anniversary: `MainMenuFrameTemplates.lua:68` — same, verified separately on this branch.
- classic_titan: `MainMenuFrameTemplates.lua:68` — same, verified separately on this branch.
- forever: `MainMenuFrameTemplates.lua:81 PlaySound(SOUNDKIT.IG_MAINMENU_CONTINUE);` **plus**
  `GameMenuFrame.lua:31 PlaySound(SOUNDKIT.IG_MAINMENU_QUIT);` (Esc handler) and
  `GameMenuFrame.lua:39 PlaySound(SOUNDKIT.IG_MAINMENU_OPEN);` (open handler).
- live: `MainMenuFrameTemplates.lua:76 PlaySound(SOUNDKIT.IG_MAINMENU_CONTINUE);` **plus**
  `GameMenuFrame.lua:31 PlaySound(SOUNDKIT.IG_MAINMENU_QUIT);` and
  `GameMenuFrame.lua:39 PlaySound(SOUNDKIT.IG_MAINMENU_OPEN);`.

### 3.3 Q2 answer: does the shipped tree replace ANY global the game menu path touches?

**No — on classic_era, on classic_anniversary, on classic_titan, on forever and on live.**

The four globals the tree replaces (`GetGameMessageInfo`, `PlayVocalErrorSoundID`,
`InspectGuildFrame_Update`, `SlashCmdList`) and the two Blizzard table fields it replaces
(`UIErrorsFrame.AddMessage`, `C_Sound.PlayVocalErrorSound`) appear **nowhere** in the game menu path on
any branch — the game-menu folders contain **0** hits for `GetGameMessageInfo`, `UIErrorsFrame`,
`VoiceUtils` and `InspectGuildFrame_Update` on classic_era, classic_anniversary, classic_titan,
forever and live.

The only overlaps are **additive, not replacements**:
`GameTooltip` (Mixin adds fields), `GameTooltip_SetDefaultAnchor` (post-hook),
`GameTooltip.FadeOut` (post-hook), `StaticPopupDialogs` (one added key).

**The carrier that was fixed is not present anywhere in the current tree.** `PlaySound` is not
replaced on classic_era, classic_anniversary, classic_titan, forever or live: the only `PlaySound`
identifier in the shipped tree is in comments (`LibForeverInspector.lua:4969-4984`, `:5037-5040`) and in
`TacoTip_Extras/RankBrowser.lua:1236-1239`, where it is **called** (`pcall(_G.PlaySound, sound)`), not
replaced.

---

## 4. Q4 + Q11 — the backdrop API surface of the shared `GameTooltip`, per branch

### 4.1 classic_era

- `Blizzard_SharedXML/Classic/GameTooltipTemplate.xml:22` —
  `<GameTooltip name="GameTooltipTemplate" clampedToScreen="true" inherits="GameTooltipCommonTemplate, TooltipBackdropTemplate" mixin="GameTooltipMixin" virtual="true">`
  → **the shared GameTooltip template DOES inherit `TooltipBackdropTemplate` on classic_era.**
- `Blizzard_SharedXML/SharedTooltipTemplates.xml:104` —
  `<Frame name="TooltipBackdropTemplate" mixin="TooltipBackdropTemplateMixin" virtual="true">`
- `Blizzard_SharedXML/SharedTooltipTemplates.xml:109` —
  `<Frame parentKey="NineSlice" inherits="NineSlicePanelTemplate" useParentLevel="true"/>`
  → **classic_era HAS a `NineSlice` child.**
- `Blizzard_SharedXML/SharedTooltipTemplates.lua:226` `TooltipBackdropTemplateMixin = {};` — it provides
  `SetBackdropColor` (`:243`), `SetBackdropBorderColor` (`:251`), `SetBorderBlendMode` (`:259`) and
  `TooltipBackdropOnLoad` (`:228`) but **no `SetBackdrop`**.
  → **classic_era's shared `GameTooltip` has NO `SetBackdrop`.**
- `Blizzard_SharedXML/Backdrop.lua:336` `function BackdropTemplateMixin:SetBackdrop(backdropInfo)` — this
  is the method the `Mixin` would graft; `BackdropTemplateMixin` is at `Backdrop.lua:142`.

### 4.2 classic_anniversary

Same three citations, read separately on this branch:
`Blizzard_SharedXML/Classic/GameTooltipTemplate.xml:22` (inherits `TooltipBackdropTemplate`),
`Blizzard_SharedXML/SharedTooltipTemplates.xml:104` (`TooltipBackdropTemplate`, mixin
`TooltipBackdropTemplateMixin`), `Blizzard_SharedXML/SharedTooltipTemplates.xml:109` (NineSlice child),
`Blizzard_SharedXML/SharedTooltipTemplates.lua:226` (mixin, no `SetBackdrop`),
`Blizzard_SharedXML/Backdrop.lua:336` (`BackdropTemplateMixin:SetBackdrop`).
→ **classic_anniversary HAS a NineSlice child and has NO `SetBackdrop`.**

### 4.3 classic_titan

Same three citations, read separately on this branch:
`Blizzard_SharedXML/Classic/GameTooltipTemplate.xml:22`,
`Blizzard_SharedXML/SharedTooltipTemplates.xml:104` and `:109`,
`Blizzard_SharedXML/SharedTooltipTemplates.lua:226`,
`Blizzard_SharedXML/Backdrop.lua:336`.
→ **classic_titan HAS a NineSlice child and has NO `SetBackdrop`.**

### 4.4 forever

- `Blizzard_GameTooltip/Mainline/GameTooltip.xml:4` —
  `<GameTooltip name="GameTooltipTemplate" mixin="GameTooltipDataMixin" inherits="SharedTooltipTemplate" virtual="true">`
  → forever's template inherits `SharedTooltipTemplate`, **not** `TooltipBackdropTemplate`.
- `Blizzard_SharedXML/SharedTooltipTemplates.xml:95` —
  `<GameTooltip name="SharedTooltipTemplate" inherits="SharedTooltipArtTemplate" … virtual="true">`
- `Blizzard_SharedXML/SharedTooltipTemplates.xml:10` —
  `<GameTooltip name="SharedTooltipArtTemplate" … virtual="true">` — **no `mixin` attribute**, so it
  carries no `BackdropTemplateMixin`.
- `Blizzard_SharedXML/SharedTooltipTemplates.xml:19` —
  `<Frame parentKey="NineSlice" inherits="NineSlicePanelTemplate" useParentLevel="true"/>`
  → **forever HAS a `NineSlice` child** and **NO `SetBackdrop`**.
- `Blizzard_SharedXML/Backdrop.lua:336` — `BackdropTemplateMixin:SetBackdrop` exists on forever.

### 4.5 live

Same four citations, read separately on this branch:
`Blizzard_GameTooltip/Mainline/GameTooltip.xml:4`,
`Blizzard_SharedXML/SharedTooltipTemplates.xml:95`, `:10`, `:19`,
`Blizzard_SharedXML/Backdrop.lua:336`.
→ **live HAS a `NineSlice` child and has NO `SetBackdrop`.**

### 4.6 Consequence for `main.lua`

`main.lua:563-566`:

```lua
local needsMixin = _G.GameTooltip
    and not _G.GameTooltip.NineSlice
    and _G.BackdropTemplateMixin
    and not _G.GameTooltip.SetBackdrop
```

The guard requires **no `NineSlice`**. A `NineSlice` child exists on classic_era, on
classic_anniversary, on classic_titan, on forever and on live. Therefore:

- **classic_era: the `Mixin(_G.GameTooltip, _G.BackdropTemplateMixin)` guard does NOT fire.**
- **classic_anniversary: does NOT fire.**
- **classic_titan: does NOT fire.**
- **forever: does NOT fire.**
- **live: does NOT fire.**

The per-tooltip Mixin at `main.lua:1089-1091` is likewise skipped, because `main.lua:1075`
(`if (tooltip.NineSlice) then`) takes the NineSlice branch on every branch.

---

## 5. Q5 + Q12 — `InspectGuildFrame_Update`, per branch

Method: whole-tree sweep `git grep -n "InspectGuildFrame_Update" origin/<branch>` (whole tree, not only
`Interface/`) plus a sweep of `Interface/AddOns/Blizzard_APIDocumentationGenerated/`.

| branch | exists? | Lua or engine? | definition site | our tree replaces it? | on the game menu path? |
|---|---|---|---|---|---|
| **classic_era** | **NO** — 0 hits in the whole tree; 0 hits in the generated API docs | neither — the identifier does not exist on this branch | — | **NO** — `main.lua:4083` `rawget(_G,"InspectGuildFrame_Update")` is nil, `main.lua:4084` returns false | **NO** — 0 hits in `Interface/AddOns/Blizzard_GameMenu/` |
| **classic_anniversary** | **NO** — 0 hits; 0 API-doc hits | neither | — | **NO** | **NO** |
| **classic_titan** | **NO** — 0 hits; 0 API-doc hits | neither | — | **NO** | **NO** |
| **forever** | **YES** | **Lua** (0 API-doc hits) | `Interface/AddOns/Blizzard_InspectUI/Mainline/InspectGuildFrame.lua:17` and a second copy at `Interface/AddOns/Blizzard_InspectUI/Camelot/InspectGuildFrame.lua:17` | **YES** — `main.lua:4087` replaces it | **NO** — 0 hits in `Interface/AddOns/Blizzard_GameMenu/` |
| **live** | **YES** | **Lua** (0 API-doc hits) | `Interface/AddOns/Blizzard_InspectUI/Mainline/InspectGuildFrame.lua:17` | **YES** — `main.lua:4087` replaces it | **NO** — 0 hits in `Interface/AddOns/Blizzard_GameMenu/` |

The forever/live definition, quoted:

```lua
17  function InspectGuildFrame_Update()
18      local guildPoints, guildNumMembers, guildName, guildRealmName = C_PaperDollInfo.GetInspectGuildInfo(InspectFrame.unit);
19      local _, guildFactionName = UnitFactionGroup(InspectFrame.unit);
20
21      InspectGuildFrame.guildName:SetText(guildName);
22      InspectGuildFrame.guildRealmName:SetFormattedText(INSPECT_GUILD_REALM, guildRealmName);
...
```

It is called from `InspectGuildFrame_OnEvent` (`forever`/`live` `InspectGuildFrame.lua:8`) and
`InspectGuildFrame_OnShow` (`:14`).

**Per-branch answer to the brief's question:** the replacement at `main.lua:4087` happens on
**forever** and on **live** only. On classic_era, classic_anniversary and classic_titan the guard at
`main.lua:4083-4084` finds nothing and the global is left alone. The game menu path calls
`InspectGuildFrame_Update` on **no** branch.

---

## 6. Q6 — `StaticPopupDialogs`, per branch

`StaticPopupDialogs` is a Blizzard table on every branch:
`Interface/AddOns/Blizzard_StaticPopup/StaticPopup.lua:21` — `StaticPopupDialogs = {}; -- Definitions`
(verified separately on classic_era, classic_anniversary, classic_titan, forever and live — same file,
same line).

**Which static-popup functions touch the table?**

- `StaticPopup_Visible` does **NOT** read it. `StaticPopup.lua:140-151`:

```lua
140  local function SecureStaticPopup_Visible(which)
141      for _, dialog in ipairs(shownDialogFrames) do
142          if dialog.which == which then
143              return dialog:GetName(), dialog;
144          end
145      end
146      return nil;
147  end
148
149  function StaticPopup_Visible(which)
150      return securecallfunction(SecureStaticPopup_Visible, which);
151  end
```

  It walks the **local** `shownDialogFrames`, not `StaticPopupDialogs`.
- `StaticPopup_Show` **does** read it. `StaticPopup.lua:279`:
  `local dialogInfo = StaticPopupDialogs[which];` (and `:127` in `StaticPopup_FindVisible`, plus
  `:265`, `:442`, `:558`, `:593`, `:622`, `:649`, `:743`, `:769`, `:785`, `:928`).
- `StaticPopup_AddDefinition` writes it (`:29`).

**Per-branch, does the game menu path read or write `StaticPopupDialogs`?**

| branch | game menu writes `StaticPopupDialogs` | game menu reads it (via `StaticPopup_Show`) | game menu reads it via `StaticPopup_Visible` | on the game menu's path at all? |
|---|---|---|---|---|
| **classic_era** | **NO** — 0 hits for `StaticPopupDialogs` in `Blizzard_GameMenu/` | **NO** — 0 `StaticPopup_Show` calls in the folder | `GameMenuFrame.lua:157` — but that reads `shownDialogFrames`, not the table | **NO** |
| **classic_anniversary** | **NO** — 0 hits | **NO** | `GameMenuFrame.lua:157` — same | **NO** |
| **classic_titan** | **YES** — `GameMenuFrame.lua:6` `StaticPopupDialogs["GAMEMENU_EXTERNALEVENT_FAILURE"] = {…}` (file scope, at load) | **YES** — `GameMenuFrame.lua:87 StaticPopup_Show("GAMEMENU_EXTERNALEVENT_FAILURE");` | `GameMenuFrame.lua:185` | **YES** |
| **forever** | **YES** — `GameMenuFrame.lua:6` | **YES** — `GameMenuFrame.lua:123 StaticPopup_Show("GAMEMENU_EXTERNALEVENT_FAILURE");` | `GameMenuFrame.lua:262`; also `WoWLabs/GameMenuFrame.xml:62`, `:78` | **YES** |
| **live** | **YES** — `GameMenuFrame.lua:6` | **YES** — `GameMenuFrame.lua:110 StaticPopup_Show("GAMEMENU_EXTERNALEVENT_FAILURE");` | `GameMenuFrame.lua:214`; also `WoWLabs/GameMenuFrame.xml:62`, `:78` | **YES** |

**Our write:** `main.lua:5154 rawset(StaticPopupDialogs, "_TacoTipDragButtonConfirm_", {...})` adds ONE
new key to a Blizzard table. It replaces neither the table nor any existing key. On classic_era and
classic_anniversary the table is not on the game menu's path at all; on classic_titan, forever and live
it is, but only through the `GAMEMENU_EXTERNALEVENT_FAILURE` key, which our write does not touch.

**Note (for the record, not a proposal):** the client's own `StaticPopup_Show` is wrapped by Blizzard in
`securecall("StaticPopup_Show", ...)` (e.g. `Blizzard_CatalogShopRefundFlow/Blizzard_CatalogShopRefundFlow_Outbound.lua:9`
on classic_era).

---

## 7. Q7 + Q10 — the containment API: `securecall`, per branch

### 7.1 It is an engine global on every branch — VERIFIED per branch

There is **no Lua definition of `securecall` anywhere** in the mirror on any branch. It is captured as a
local, which is only possible if the global already exists:

| branch | capture site |
|---|---|
| **classic_era** | `Interface/AddOns/Blizzard_FrameXML/SharedPetBattleTemplates.lua:5 local securecall = securecall;` (also `Blizzard_PrintHandler/Blizzard_PrintHandler.lua:5`, `Blizzard_RestrictedAddOnEnvironment/RestrictedFrames.lua:22`, `…/SecureHandlers.lua:17`, `Blizzard_SharedXML/CircularBuffer.lua:1`, `Blizzard_SharedXML/Classic/UIDropDownMenu.lua:26`, `Blizzard_SharedXMLBase/ProxyUtil.lua:8`) |
| **classic_anniversary** | same seven sites, read separately on this branch |
| **classic_titan** | same seven sites, read separately on this branch |
| **forever** | `Blizzard_FrameXML/SharedPetBattleTemplates.lua:5` (also `Blizzard_PrintHandler/Blizzard_PrintHandler.lua:5`, `Blizzard_RestrictedAddOnEnvironment/RestrictedFrames.lua:22`, `…/SecureHandlers.lua:17`, `Blizzard_SharedXML/CircularBuffer.lua:1`, `Blizzard_SharedXML/Mainline/UIDropDownMenu.lua:25`, `Blizzard_SharedXMLBase/ProxyUtil.lua:8`) |
| **live** | same seven sites, read separately on this branch |

`securecall` does **not** appear in the generated API docs on any branch; the only related entry is
`Name = "securecallmethod"` (`Blizzard_APIDocumentationGenerated/FrameScriptDocumentation.lua:379` on
classic_era, `:379` on classic_anniversary, `:388` on classic_titan, `:443` on forever, `:443` on live).

### 7.2 Occurrence counts, per branch

Command: `git -C /home/sam/wow-ui-source grep -o "securecall(" origin/<branch> -- 'Interface/' | wc -l`
(the literal `securecall(`, so `securecallfunction(` is not counted).

| branch | `securecall(` occurrences | of which string-first (`securecall("…"` ) | of which function-first |
|---|---|---|---|
| **classic_era** | **174** | 131 | 43 |
| **classic_anniversary** | **174** | 131 | 43 |
| **classic_titan** | **174** | 131 | 43 |
| **forever** | **124** | 81 | 43 |
| **live** | **123** | 80 | 43 |

### 7.3 Two call shapes, both present on every branch

**Shape A — string first (calls a global by name).** Examples:

| branch | call site |
|---|---|
| **classic_era** | `Interface/AddOns/Blizzard_CatalogShop/Blizzard_CatalogShop_Outbound.lua:9 securecall("UpdateMicroButtons");` and `Interface/AddOns/Blizzard_StoreUI/Classic/Blizzard_StoreUIOutbound.lua:25 securecall("Logout");` |
| **classic_anniversary** | `Blizzard_CatalogShop/Blizzard_CatalogShop_Outbound.lua:9` and `Blizzard_StoreUI/Classic/Blizzard_StoreUIOutbound.lua:25` — verified separately |
| **classic_titan** | `Blizzard_CatalogShop/Blizzard_CatalogShop_Outbound.lua:9` and `Blizzard_StoreUI/Classic/Blizzard_StoreUIOutbound.lua:25` — verified separately |
| **forever** | `Blizzard_CatalogShop/Blizzard_CatalogShop_Outbound.lua:9` and `Blizzard_StoreUI/Blizzard_Shared_StoreUIOutbound.lua:21 securecall("Logout");` |
| **live** | `Blizzard_CatalogShop/Blizzard_CatalogShop_Outbound.lua:9` and `Blizzard_StoreUI/Blizzard_Shared_StoreUIOutbound.lua:21 securecall("Logout");` |

Note the second one: **Blizzard itself wraps the protected `Logout` in `securecall("Logout")`** on
classic_era, classic_anniversary, classic_titan, forever and live. That is the client confirming both
that `Logout` is protected and that the string-first shape is the one Blizzard uses for it.

**Shape B — function first (calls a function value).** Examples:

| branch | call site |
|---|---|
| **classic_era** | `Interface/AddOns/Blizzard_BuffFrame/BuffFrame.lua:991 securecall(self.UpdateDuration, self, self.timeLeft); -- Taint issue with SecondsToTimeAbbrev` |
| **classic_anniversary** | `Blizzard_BuffFrame/BuffFrame.lua:991` — verified separately |
| **classic_titan** | `Blizzard_BuffFrame/BuffFrame.lua:991` — verified separately |
| **forever** | `Blizzard_BuffFrame/BuffFrame.lua:1235 securecall(self.UpdateDuration, self, self.timeLeft);` |
| **live** | `Blizzard_BuffFrame/BuffFrame.lua:961 securecall(self.UpdateDuration, self, self.timeLeft);` |

Other function-first examples, identical line numbers on every branch:
`Blizzard_ChatFrameBase/Shared/MacroExecutionManager.lua:21 local defaultEditBox = securecall(GetDefaultChatEditBox);`
and `Blizzard_Menu/Menu.lua:142 return securecall(GetMenuMixin, self);`.

**Our tree's use:** `main.lua:517-525` (`runUntainted`) and `options.lua:39` wrap the add-on callback in
`securecall` when `secureCallFn` is present, and fall back to a direct call when it is not.

---

## 8. Q8 — the shared `GameTooltip`'s declared script set, per branch

### 8.1 classic_era

Frame block — `Interface/AddOns/Blizzard_GameTooltip/Classic/GameTooltip.xml:13-35`:

```xml
13      <GameTooltip name="GameTooltip" frameStrata="TOOLTIP" hidden="true" parent="UIParent" inherits="GameTooltipTemplate">
14          <Scripts>
15              <OnLoad>
16                  GameTooltip_OnLoad(self);
17                  self.shoppingTooltips = { ShoppingTooltip1, ShoppingTooltip2 };
18                  if (BattlePetTooltip) then
19                      BattlePetTooltip:Hide();
20                  end
21              </OnLoad>
22              <OnTooltipSetUnit function="GameTooltip_OnTooltipSetUnit" />
23              <OnTooltipSetItem function="GameTooltip_OnTooltipSetItem" />
24              <OnTooltipSetSpell function="GameTooltip_OnTooltipSetSpell" />
25              <OnHide>
26                  GameTooltip_OnHide(self);
27                  ShoppingTooltip1:Hide();
28                  ShoppingTooltip2:Hide();
29                  if (BattlePetTooltip) then
30                      BattlePetTooltip:Hide();
31                  end
32              </OnHide>
33              <OnUpdate function="GameTooltip_OnUpdate"/>
34          </Scripts>
35      </GameTooltip>
```

Template block — `Interface/AddOns/Blizzard_SharedXML/Classic/GameTooltipTemplate.xml:150-156`:

```xml
150         <Scripts>
151             <OnLoad method="OnLoadGameTooltip" inherit="prepend"/>
152             <OnHide method="OnHide"/>
153             <OnTooltipSetDefaultAnchor method="OnTooltipSetDefaultAnchor"/>
154             <OnTooltipAddMoney method="OnTooltipAddMoney"/>
155             <OnTooltipCleared method="OnTooltipCleared"/>
156         </Scripts>
```

**classic_era declares:** `OnLoad`, `OnTooltipSetUnit`, `OnTooltipSetItem`, `OnTooltipSetSpell`,
`OnHide`, `OnUpdate`, `OnTooltipSetDefaultAnchor`, `OnTooltipAddMoney`, `OnTooltipCleared`.
**classic_era does NOT declare `OnShow`.**

### 8.2 classic_anniversary

Same two blocks, read separately on this branch:
`Blizzard_GameTooltip/Classic/GameTooltip.xml:13-35` (identical text) and
`Blizzard_SharedXML/Classic/GameTooltipTemplate.xml:150-156` (identical text).

**classic_anniversary declares:** the same nine scripts.
**classic_anniversary does NOT declare `OnShow`.**
(The files are byte-identical to classic_era's; that is a fact about the files, not a proof that the
two clients behave alike. The mirror offers nothing further on the difference between the two engine
builds.)

### 8.3 classic_titan

Same two blocks, read separately on this branch:
`Blizzard_GameTooltip/Classic/GameTooltip.xml:13-35` and
`Blizzard_SharedXML/Classic/GameTooltipTemplate.xml:150-156`.

**classic_titan declares:** the same nine scripts.
**classic_titan does NOT declare `OnShow`.**

### 8.4 forever

Template block — `Interface/AddOns/Blizzard_GameTooltip/Mainline/GameTooltip.xml:4` (template name) and
`:25-36`:

```xml
25          <Scripts>
26              <OnLoad inherit="prepend" function="GameTooltip_OnLoad"/>
27              <OnHide function="GameTooltip_OnHide"/>
28              <OnTooltipSetDefaultAnchor>
29                  GameTooltip_SetDefaultAnchor(self, UIParent);
30              </OnTooltipSetDefaultAnchor>
31              <OnTooltipCleared>
32                  GameTooltip_ClearMoney(self);
33                  SharedTooltip_ClearInsertedFrames(self);
34              </OnTooltipCleared>
35              <OnEvent method="OnEvent"/>
36          </Scripts>
```

Shared-template block — `Interface/AddOns/Blizzard_SharedXML/SharedTooltipTemplates.xml:95-102`:

```xml
95      <GameTooltip name="SharedTooltipTemplate" inherits="SharedTooltipArtTemplate" clampedToScreen="true" frameStrata="TOOLTIP" hidden="true" virtual="true">
96          <Scripts>
97              <OnLoad function="SharedTooltip_OnLoad"/>
98              <OnHide inherit="append" function="SharedTooltip_OnHide"/>
99              <OnTooltipSetDefaultAnchor function="SharedTooltip_SetDefaultAnchor"/>
100             <OnTooltipCleared function="SharedTooltip_ClearInsertedFrames"/>
101         </Scripts>
102     </GameTooltip>
```

Frame block — `Blizzard_GameTooltip/Mainline/GameTooltip.xml:249` (frame) and `:269-273`:

```xml
269         <Scripts>
270             <OnLoad method="OnLoad"/>
271             <OnShow function="GameTooltip_OnShow"/>
272             <OnUpdate function="GameTooltip_OnUpdate"/>
273         </Scripts>
```

**forever declares:** `OnLoad`, `OnHide`, `OnTooltipSetDefaultAnchor`, `OnTooltipCleared`, `OnEvent`,
`OnShow`, `OnUpdate`.
**forever does NOT declare `OnTooltipSetUnit`, `OnTooltipSetItem` or `OnTooltipSetSpell`.**

### 8.5 live

Same three blocks, read separately on this branch:
`Blizzard_GameTooltip/Mainline/GameTooltip.xml:4`, `:25-36`, `:249`, `:269-273`;
`Blizzard_SharedXML/SharedTooltipTemplates.xml:95-102`.

**live declares:** `OnLoad`, `OnHide`, `OnTooltipSetDefaultAnchor`, `OnTooltipCleared`, `OnEvent`,
`OnShow`, `OnUpdate`.
**live does NOT declare `OnTooltipSetUnit`, `OnTooltipSetItem` or `OnTooltipSetSpell`.**

### 8.6 Q8 consequence (client truth only)

On classic_era, classic_anniversary and classic_titan the shared `GameTooltip` has
`OnTooltipSetUnit` / `OnTooltipSetItem` / `OnTooltipSetSpell` and no `OnShow`. On forever and live it has
`OnShow` and none of the three `OnTooltipSet*` scripts. The add-on's own hook installation
(`main.lua:2946`, `:3327` and the `registerTooltipVisualClearing` list) is therefore installable on the
three classic branches for the `OnTooltipSet*` scripts and on forever and live for `OnShow`. **This is
client truth, not a proposal.**

---

## 9. Q9 — `GetGameMessageInfo` callers, per branch

`GetGameMessageInfo` is a **documented engine global** on every branch:
`Interface/AddOns/Blizzard_APIDocumentationGenerated/GameErrorDocumentation.lua:10 Name = "GetGameMessageInfo"`
(verified separately on classic_era, classic_anniversary, classic_titan, forever and live).

**Every call site in `Interface/` uses the bare global** (not `_G.GetGameMessageInfo`), so
`rawset(_G, "GetGameMessageInfo", …)` replaces the exact binding the client calls.

| branch | call sites in `Interface/` | reachable from the game menu Logout/Quit path? |
|---|---|---|
| **classic_era** | `Interface/AddOns/Blizzard_Channels/VoiceUtils.lua:82` — `local stringId = GetGameMessageInfo(gameError);`<br>`Interface/AddOns/Blizzard_UIErrorsFrame/Classic/UIErrorsFrame.lua:142` — `local errorStringId, soundKitID, voiceID = GetGameMessageInfo(messageType);` | **NO** — 0 hits for `GetGameMessageInfo` / `UIErrorsFrame` / `VoiceUtils` inside `Interface/AddOns/Blizzard_GameMenu/` |
| **classic_anniversary** | `Blizzard_Channels/VoiceUtils.lua:82`<br>`Blizzard_UIErrorsFrame/Classic/UIErrorsFrame.lua:142` — verified separately | **NO** |
| **classic_titan** | `Blizzard_Channels/VoiceUtils.lua:82`<br>`Blizzard_UIErrorsFrame/Classic/UIErrorsFrame.lua:142` — verified separately | **NO** |
| **forever** | `Blizzard_Channels/Classic/VoiceUtils.lua:82`<br>`Blizzard_Channels/Mainline/VoiceUtils.lua:88`<br>`Blizzard_UIErrorsFrame/Mainline/UIErrorsFrame.lua:150` — **THREE callers on forever** | **NO** |
| **live** | `Blizzard_Channels/VoiceUtils.lua:82`<br>`Blizzard_UIErrorsFrame/Mainline/UIErrorsFrame.lua:150` | **NO** |

The `UIErrorsFrame` caller, quoted per branch:

- classic_era `Blizzard_UIErrorsFrame/Classic/UIErrorsFrame.lua:138-149`
- classic_anniversary `Blizzard_UIErrorsFrame/Classic/UIErrorsFrame.lua:138-149`
- classic_titan `Blizzard_UIErrorsFrame/Classic/UIErrorsFrame.lua:138-149`

```lua
138 function UIErrorsMixin:TryDisplayMessage(messageType, message, r, g, b)
139     if self:ShouldDisplayMessageType(messageType, message) then
140         self:AddMessage(message, r, g, b, 1.0, messageType);
141
142         local errorStringId, soundKitID, voiceID = GetGameMessageInfo(messageType);
143         if voiceID then
144             C_Sound.PlayVocalErrorSound(voiceID);
145         elseif soundKitID then
146             PlaySound(soundKitID);
147         end
148     end
149 end
```

- forever `Blizzard_UIErrorsFrame/Mainline/UIErrorsFrame.lua:146-157` and
  live `Blizzard_UIErrorsFrame/Mainline/UIErrorsFrame.lua:146-157`:

```lua
146 function UIErrorsMixin:TryDisplayMessage(messageType, message, r, g, b)
147     if not self:GetMessagesSuppressed() and self:ShouldDisplayMessageType(messageType, message) then
148         self:AddMessage(message, r, g, b, 1.0, messageType);
149
150         local errorStringId, soundKitID, voiceID = GetGameMessageInfo(messageType);
151         if voiceID then
152             C_Sound.PlayVocalErrorSound(voiceID);
153         elseif soundKitID then
154             PlaySound(soundKitID);
155         end
156     end
157 end
```

Note `PlaySound(soundKitID)` at `:146` (classic_era / classic_anniversary / classic_titan) and `:154`
(forever / live) — the client's own global `PlaySound` call on the error path. That is the call the
removed detour used to intercept, and the reason the carrier existed on classic_era.

**Q9 answer per branch:** `GetGameMessageInfo` is reachable from the game menu Logout/Quit path on
**no** branch — classic_era: no. classic_anniversary: no. classic_titan: no. forever: no. live: no.

---

## 10. Per-branch comparison table

Every cell is VERIFIED from a command run in this lane unless marked.

| question | classic_era (11509) | classic_anniversary (20506) | classic_titan (38002) | forever (16001) | live (120105) |
|---|---|---|---|---|---|
| Game-menu closure `PlaySound` / `HideUIPanel` / `callback()` | `:67` / `:68` / `:69` | `:67` / `:68` / `:69` | `:95` / `:96` / `:97` | `:166` / `:167` / `:168` | `:118` / `:119` / `:120` |
| Extra `PlaySound` on the menu path | `MainMenuFrameTemplates.lua:68` | `MainMenuFrameTemplates.lua:68` | `MainMenuFrameTemplates.lua:68` | `MainMenuFrameTemplates.lua:81`; `GameMenuFrame.lua:31`, `:39` | `MainMenuFrameTemplates.lua:76`; `GameMenuFrame.lua:31`, `:39` |
| Logout / Quit button | `:158` / `:159` | `:158` / `:159` | `:186` / `:187` | `:263` / `:264` | `:215` / `:216` |
| `StaticPopup_Visible("QUIT")` | `:157` | `:157` | `:185` | `:262` | `:214` |
| Game menu writes `StaticPopupDialogs` | no | no | **yes** `:6` | **yes** `:6` | **yes** `:6` |
| Game menu reads `StaticPopupDialogs` (via `StaticPopup_Show`) | no | no | **yes** `:87` | **yes** `:123` | **yes** `:110` |
| Our tree replaces a game-menu global? | **no** | **no** | **no** | **no** | **no** |
| `GetGameMessageInfo` replaced by our tree? | **yes** (Classic Era only) | no | no | no | no |
| `GetGameMessageInfo` caller count in `Interface/` | 2 | 2 | 2 | **3** | 2 |
| `GetGameMessageInfo` reachable from the menu path? | no | no | no | no | no |
| `PlayVocalErrorSoundID` replaced by our tree? | **yes** | no | no | no | no |
| `InspectGuildFrame_Update` exists? | **no** | **no** | **no** | **yes** (Lua, `Blizzard_InspectUI/Mainline/InspectGuildFrame.lua:17`) | **yes** (Lua, same path) |
| `InspectGuildFrame_Update` replaced by our tree? | no (guard returns false) | no | no | **yes** | **yes** |
| `InspectGuildFrame_Update` on the menu path? | no | no | no | no | no |
| Global `GameTooltipStatusBar` identifier in the tree | 0 literal hits (3 mixin/XML hits) | 0 literal hits | 0 literal hits | 0 hits | 0 hits |
| `$parentStatusBar` template child present? | **yes** (`GameTooltipTemplate.xml:138`) | **yes** (`:138`) | **yes** (`:138`) | **yes** (`GameTooltip.xml:9`) | **yes** (`GameTooltip.xml:9`) |
| StatusBar mixin on that child | `GameTooltipStatusBarMixin` | `GameTooltipStatusBarMixin` | `GameTooltipStatusBarMixin` | `GameTooltipUnitHealthBarMixin` | `GameTooltipUnitHealthBarMixin` |
| Shared `GameTooltip` template inherits `TooltipBackdropTemplate`? | **yes** (`GameTooltipTemplate.xml:22`) | **yes** (`:22`) | **yes** (`:22`) | no (`GameTooltip.xml:4` → `SharedTooltipTemplate`) | no (`GameTooltip.xml:4` → `SharedTooltipTemplate`) |
| Shared `GameTooltip` has a `NineSlice` child? | **yes** (`SharedTooltipTemplates.xml:109`) | **yes** (`:109`) | **yes** (`:109`) | **yes** (`SharedTooltipTemplates.xml:19`) | **yes** (`:19`) |
| Shared `GameTooltip` has `SetBackdrop`? | **no** | **no** | **no** | **no** | **no** |
| `Mixin(GameTooltip, BackdropTemplateMixin)` guard fires? | **no** | **no** | **no** | **no** | **no** |
| Shared `GameTooltip` declares `OnShow`? | **no** | **no** | **no** | **yes** (`GameTooltip.xml:271`) | **yes** (`:271`) |
| Shared `GameTooltip` declares `OnTooltipSetUnit/Item/Spell`? | **yes** (`:22`,`:23`,`:24`) | **yes** | **yes** | **no** | **no** |
| `securecall` is an engine global | yes | yes | yes | yes | yes |
| `securecall(` occurrences in `Interface/` | 174 | 174 | 174 | 124 | 123 |
| `securecall` string-first / function-first | 131 / 43 | 131 / 43 | 131 / 43 | 81 / 43 | 80 / 43 |
| `securecall` captured as a local | yes (`SharedPetBattleTemplates.lua:5`) | yes | yes | yes | yes |
| Blizzard wraps `Logout` in `securecall("Logout")` | yes (`Blizzard_StoreUI/Classic/Blizzard_StoreUIOutbound.lua:25`) | yes | yes | yes (`Blizzard_StoreUI/Blizzard_Shared_StoreUIOutbound.lua:21`) | yes (`:21`) |

---

## 11. Corrections to standing knowledge

1. **`bench/audits/2026-10-20-quit-taint.md` §4, the `main.lua:3678-3685` row, is WRONG as an absence
   claim.** It states: *"`GameTooltipStatusBar:HookScript("OnHide", …)` — **never runs** — there is
   **no global `GameTooltipStatusBar` on any branch**; the client only has the *mixin*
   `GameTooltipStatusBarMixin` … and the `$parentStatusBar` frame … The `if (GameTooltipStatusBar) then`
   guard is false everywhere."* The audit did not sweep the XML for `$parentStatusBar`, and on
   classic_era, classic_anniversary, classic_titan, forever and live the shared `GameTooltip` template
   **does** declare a `<StatusBar name="$parentStatusBar">` child (classic_era /
   classic_anniversary / classic_titan: `Blizzard_SharedXML/Classic/GameTooltipTemplate.xml:138`;
   forever / live: `Blizzard_GameTooltip/Mainline/GameTooltip.xml:9`), and the `GameTooltip` frame
   inherits that template on every branch. The mechanism that turns such a `$parent` child into a Lua
   global is demonstrated in the same files: `$parentTextLeft1` → `GameTooltipTextLeft1`, which
   Blizzard's own Lua uses as a bare global on every branch
   (classic_era `Blizzard_AuctionHouseUI/Shared/Blizzard_AuctionHouseBuyDialog.lua:36` and `:47`,
   `Blizzard_UnitFrame/Classic/UnitFrame.lua:460`; classic_anniversary the same three;
   classic_titan the same three; forever `Blizzard_AuctionHouseUI/Shared/Blizzard_AuctionHouseBuyDialog.lua:36`
   and `:47` plus `Blizzard_UIPanels_Game/Mainline/QuestMapFrame.lua:2223`; live
   `Blizzard_AuctionHouseUI/Shared/Blizzard_AuctionHouseBuyDialog.lua:36` and `:47` plus
   `Blizzard_UIPanels_Game/Mainline/QuestMapFrame.lua:2124`). Per `CAIRN.md`, the old row was an
   absence claim without the required whole-tree sweep plus generated API docs; it must be withdrawn.
   **What our tree does with the name** (all VERIFIED from the repo): `main.lua:1642-1643`,
   `main.lua:2818-2819`, and `main.lua:3789-3796`
   (`if (GameTooltipStatusBar) then GameTooltipStatusBar:HookScript("OnHide", function() … end) end` —
   an add-on script hook installed on a Blizzard frame).
2. **`bench/audits/2026-10-21-quit-taint-carrier.md` §4, "exactly two places", is per-branch wrong.**
   `GetGameMessageInfo` has **two** callers on classic_era (`Blizzard_Channels/VoiceUtils.lua:82`,
   `Blizzard_UIErrorsFrame/Classic/UIErrorsFrame.lua:142`), on classic_anniversary (same two), on
   classic_titan (same two) and on live (`Blizzard_Channels/VoiceUtils.lua:82`,
   `Blizzard_UIErrorsFrame/Mainline/UIErrorsFrame.lua:150`), but **three** on forever
   (`Blizzard_Channels/Classic/VoiceUtils.lua:82`, `Blizzard_Channels/Mainline/VoiceUtils.lua:88`,
   `Blizzard_UIErrorsFrame/Mainline/UIErrorsFrame.lua:150`).
3. **`bench/audits/2026-10-20-quit-taint.md` §5, the `securecall(` count, does not reproduce.**
   That audit says *"the client source uses `securecall(` 34× on each classic branch, 30× on forever and
   live"*. The command `git grep -o "securecall(" origin/<branch> -- 'Interface/' | wc -l` gives
   **174** on classic_era, **174** on classic_anniversary, **174** on classic_titan, **124** on forever
   and **123** on live. The 34/30 figure is from some narrower scope that the audit did not record;
   the counts above are reproducible and should replace it.
4. **`main.lua`'s own comment at `:546-562` describes a "legacy template" that no shipped client has.**
   It says the early `Mixin` "provides a fallback for any client whose tooltip template lacks NineSlice",
   and that on Retail and WoW Forever the template "provides a NineSlice child and does NOT mix in
   BackdropTemplateMixin". The mirror shows that the **classic** template also provides a NineSlice
   child — classic_era, classic_anniversary and classic_titan all reach it through
   `GameTooltipTemplate` → `TooltipBackdropTemplate` → `<Frame parentKey="NineSlice" …/>`
   (`Blizzard_SharedXML/SharedTooltipTemplates.xml:109`). So the guard at `main.lua:563-566` fires on
   **no** branch at all: **classic_era, classic_anniversary, classic_titan, forever, live — none.**
5. **The carrier audit's §2.1 line table is right for every branch, and the `PlaySound` detour is gone
   from the tree.** `grep -rn "PlaySound" --include='*.lua'` over the shipped tree finds only comments
   (`LibForeverInspector.lua:4969-4984`, `:5037-5040`) and one **call**,
   `TacoTip_Extras/RankBrowser.lua:1236-1239`. **classic_era: not replaced. classic_anniversary: not
   replaced. classic_titan: not replaced. forever: not replaced. live: not replaced.**

---

## 12. What I could not establish

1. **Whether `GameTooltipStatusBar` is a live Lua global at runtime on any branch.** The mirror
   contains no engine code and no XML loader, so the "named XML child → global" step cannot be read.
   What is VERIFIED per branch: the literal identifier `GameTooltipStatusBar` appears **nowhere** in
   the whole mirror tree (whole-tree sweep, all five branches) and **nowhere** in the generated API
   docs (all five branches); the `<StatusBar name="$parentStatusBar">` child **is** declared in the
   shared `GameTooltip` template on all five branches; and the *same* declaration mechanism is proven
   to produce a global for the sibling `$parentTextLeft1` → `GameTooltipTextLeft1` on all five
   branches (Blizzard's own Lua uses it as a bare global on all five). The remaining step — that a
   `<Frames>` child with a `name` is registered as a global the same way a `<Layers>` child is — is
   **ASSUMED**, not verified. It is the only thing standing between "the identifier is absent from the
   source" and "`main.lua:3789` installs an add-on `OnHide` hook on a Blizzard frame at load time".
   I could not close it from the mirror: every `$parent` child I could resolve to a concrete name
   (`$parentTextLeft1` → `GameTooltipTextLeft1`) is a `<Layers>` region, and the `<Frames>` cases I
   could resolve (`MirrorTimer1/2/3` from `MirrorTimerTemplate`,
   `Blizzard_FrameXML/Classic/MirrorTimer.xml:55`, `:60`, `:65`) are **not** referenced as globals
   anywhere in the tree (0 hits for `MirrorTimer1StatusBar` on classic_era).
2. **Whether the classic_era and classic_anniversary clients behave alike.** Their
   `GameMenuFrame.lua`, `GameMenuFrame.xml`, `GameTooltip.xml`, `GameTooltipTemplate.xml` and
   `MainMenuFrameTemplates.lua` are byte-identical (only line endings differ). The mirror carries no
   engine code and no per-client build metadata beyond the branch name, so it **cannot** settle any
   behavioural difference between the two 1.15.9 / 2.5.x engine builds. The same applies to
   classic_titan, forever and live against their own file sets.
3. **The taint-propagation rule itself.** The mirror has no engine code. That a replaced global taints
   the closure that calls it is the standard rule and the reason `hooksecurefunc` exists, but it is
   not written down in any `.lua` in `/home/sam/wow-ui-source`. **ASSUMED**, with Blizzard's own use
   of `securecall` as the supporting argument.
4. **Which of the five branches the operator has actually run.** There is no in-game observation in
   this lane's inputs beyond the operator's own report of the Classic Era refusal recorded in
   `bench/audits/2026-10-21-quit-taint-carrier.md`. The other four clients are **UNKNOWN** in
   behaviour; this artifact reports only what the source says.
5. **Whether `SlashCmdList` exists at addon-load time on each branch.** The repo-side fact is VERIFIED
   (the write is guarded by `rawget(_G,"SlashCmdList") == nil`). Whether the guard fires per branch
   needs the per-branch `ChatFrameSetup.lua` load order, which this lane did not read.
6. **Whether `HideUIPanel` resolves to the UI-panel version or the Glue version on each branch.**
   Both are defined on every branch — e.g. classic_era
   `Blizzard_UIParentPanelManager/Shared/UIParentPanelManager.lua:853` and
   `Blizzard_GlueParent/Classic/GlueParent.lua:719` — and which one is live depends on load order
   (the last definition wins). This lane did not resolve that per branch; it does not affect any
   conclusion here, because the tree replaces neither.

---

## 13. Validation bar

1. **Mirror untouched** — `git -C /home/sam/wow-ui-source status --porcelain` →
   `?? .vscode/`, `?? SKILL.md`, `?? reference/`, byte-identical to the baseline captured at desk-open
   (`diff` of the two outputs: no differences). **PASS.**
2. **No product file touched** — `git -C /home/sam/TacoTip-Gearscore-TBC status --short` differs from
   the desk-open baseline only by `?? desks/taint-crossclient-2026-10-21/` and
   `?? bench/audits/2026-10-21-crossclient-taint-surfaces.md`. **PASS.**
3. **Every `path:line` was produced by a command run in this lane** — the commands are listed in the
   desk journal `desks/taint-crossclient-2026-10-21/journal.md`, steps 2-10, and every one of them is a
   `git -C /home/sam/wow-ui-source show|grep|ls-tree` or a repo grep/read.
4. **Every client claim names its branch and carries an evidence label.** **PASS.**
