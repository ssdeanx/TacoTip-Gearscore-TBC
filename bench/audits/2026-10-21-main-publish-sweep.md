# Main add-on — publish-ready sweep

- **desk:** `main-publish-sweep-2026-10-21` · **date:** 2026-10-21
  · **run_id:** `mainpublishsweep20261021`
- **kind:** READ-ONLY client-source + repo sweep of the MAIN add-on. **No product
  file was modified.** Writes were limited to this desk and this artifact.
- **supersedes:** nothing. It **confirms** `bench/audits/2026-10-21-quit-taint-carrier.md`
  on every point it re-checked, and **adds one method correction** to it (B7 §7.6).
- **evidence labels:** VERIFIED / ASSUMED / UNKNOWN, per `CAIRN.md`.
- **method:** `git -C /home/sam/wow-ui-source show origin/<branch>:<path>`,
  `git -C /home/sam/wow-ui-source grep -w -l <name> origin/<branch> -- Interface/`,
  `git -C /home/sam/wow-ui-source ls-tree -r --name-only origin/<branch>` — all
  read-only. Repo reads and `git diff HEAD -- <file>`. No web.

---

## 0. The five clients, and how a branch is named in this artifact

| label | branch | build |
| :--- | :--- | :--- |
| classic_era | `origin/classic_era` | 11509 |
| classic_anniversary | `origin/classic_anniversary` | 20506 |
| classic_titan | `origin/classic_titan` | 38002 |
| forever | `origin/forever` | 16001 |
| live | `origin/live` | 120105 |

Five separate clients, not two families. Every client claim below names its branch.

---

## 1. B1 — the eight invariants, verified against the tree

`workshop.md` -> "the invariants — do not touch" is the list. Each is checked
below against the **current working tree**, and against `git diff HEAD -- <file>`.

### 1.0 The working tree vs the last commit (context for every verdict)

`git diff --stat HEAD -- main.lua options.lua gearscore.lua pawn.lua textures.lua TacoTip.toc Locale/ Libs/`
shows `4037 insertions(+), 1041 deletions(-)`. That number is misleading: **the whole
shipped tree is CRLF at HEAD and LF in the working tree** (`git show HEAD:gearscore.lua
| file -` -> "with CRLF line terminators"; `file gearscore.lua` -> "UTF-8 text"), and
`.gitattributes` now carries `* text=auto eol=lf`. After normalising line endings and
dropping blank lines, the real content delta is:

| file | changed lines after normalisation |
| :--- | :--- |
| `gearscore.lua` | 246 |
| `main.lua` | 1697 |
| `options.lua` | 768 |
| `pawn.lua` | 150 |
| `textures.lua` | **0** (byte-identical modulo line endings) |
| `TacoTip.toc` | 4 |

**VERIFIED.** Nothing below is a line-ending artefact.

### 1.1 The classic-era inspect range gate — **HOLDS**

| item | file:line | value | vs HEAD |
| :--- | :--- | :--- | :--- |
| `NEARBY_ASK_YARDS` | `Libs/LibForeverInspector/LibForeverInspector.lua:484` | `isClassic and 20 or 40` | identical |
| `INSPECT_INTERACT_DISTANCE_INDEX` | `Libs/LibForeverInspector/LibForeverInspector.lua:466` | `1` | identical |
| distance pre-filter | `LibForeverInspector.lua:5134-5138` (`isCloseEnoughToAsk`, squared compare) | unchanged | identical |
| distance-FIRST ordering (library) | `LibForeverInspector.lua:4111-4143` | on the classic family the distance signal is read before the `CanInspect` query | unchanged |
| distance-FIRST ordering (request) | `LibForeverInspector.lua:4551-4560` | on `isClassic`, `probeInteractDistance` runs **before** `probeCanInspect`; the other four keep the shipped order | unchanged |
| probe guard | `LibForeverInspector.lua:5063-5078` (`probeCanInspect`), `:5080-5094` (`probeInteractDistance`) | every engine inspect call is `pcall`d and arms a 0.5 s attribution window | unchanged |
| learned ceiling | `LibForeverInspector.lua:4502-4509` (`exceedsLearnedRangeImpl`) | squared-distance compare against `lib.inspectRangeLimit[lib.family]` | unchanged |
| `INSPECT_DELAY` | `:4039` | `(isRetail or isForever) and 0.4 or 1.0` | identical |
| `INSPECT_PENDING_TIMEOUT` | `:4052` | `3.0` | identical |
| `CACHE_REFRESH_DELAY` | `:4053` | `300` | identical |
| `INSPECT_REJECT_COOLDOWN` | `:4357` | `10.0` | identical |
| `INSPECT_GUARD_WINDOW` | `:4727` | `0.5` | identical |
| `MAX_TALENTS_PER_TAB` / `MAX_LINEAR_TALENTS` / `MAX_GRID_TIERS` / `MAX_GRID_COLUMNS` / `MAX_ICON_QUERIES` | `:217` / `:3432` / `:3433` / `:3434` / `:3437` | `31` / `40` / `20` / `5` / `120` | identical |

**VERIFIED.** The whole gate is byte-identical to the last commit.

### 1.2 The gearscore formula — **HOLDS**

`gearscore.lua`:
- the whole `GS_ItemTypes` `SlotMOD` table: `grep -oE '\["SlotMOD"\] = [0-9.]+'` on
  `git show HEAD:gearscore.lua` and on the working tree gives the **same md5**
  (`3199549c16704b305432628ac9fab472`) — every `SlotMOD` is unchanged. VERIFIED.
- `ITEM_BAND_SCALE = 11.25` (`gearscore.lua:504`) — unchanged. VERIFIED.
- `Scale = 1.8618` / `0.005` / `1` and `QualityScale = 1` / `1.3` / `0.005`
  (`gearscore.lua:520-530`) — unchanged. VERIFIED.
- the A/B/C tables and the quality ramp — the numeric-literal multiset of the whole
  file differs from HEAD by exactly three counts: `0` (29->30), `1` (16->18) and
  `1000` (1->2). The two new `0`/`1` are the slash-forwarding error counter
  (`(TT.ev.extrasForwardFailed or 0) + 1`); the extra `1000` is `BRACKET_SIZE = 1000`
  in the Unknown branch (see 1.3). **No formula literal moved.** VERIFIED.
- the hunter factors: `GearScore = floor(GearScore * 5.3224)` (`gearscore.lua:621`)
  and `TempScore = TempScore * 5.3224` (`:779`) — identical to HEAD's `:377` / `:533`. VERIFIED.
- titan grip: `local TitanGrip = 1` (`:668`), `local OffHandTitanGrip = 1` (`:747`),
  `TitanGrip = 0.5` (`:752`), `OffHandTitanGrip = 0.5` (`:755`) — identical to HEAD's
  `:422` / `:501` / `:506` / `:509`. VERIFIED.

### 1.3 The retail bracket — **HOLDS at the shared 1000**

`gearscore.lua:382` `local BRACKET_SIZE = 1000`; `:385` Classic -> 200;
`:387` TBC -> 400; `:389` Forever -> 200; `:396` Unknown -> 1000.
Titanforge is **not** Classic/TBC/Forever (`LibForeverInspector.lua:198-211`:
`family = "titanforge"`), so it falls through to the 1000 default, as does retail
(`family = "retail"`). The Retail-only special case is absent — the operator hold
documented at `gearscore.lua:369-376` is in force. VERIFIED.

### 1.4 The wire format — **HOLDS (it lives in the companion add-on)**

The main add-on's `.toc` does not load a socket layer; the wire is
`TacoTip_Extras/RankSync.lua` (read-only here, not written):
- `WIRE_VERSION = "2"` (`RankSync.lua:175`) and the record head is `"R"` + version
  (`:187-188`) -> **`R;2`**. VERIFIED.
- `RECORD_FIELDS = 13` (`RankSync.lua:212`), and `SerializeRecord` (`:186-201`)
  emits exactly 13 parts; `DeserializeRecord` refuses anything shorter
  (`:246`). VERIFIED.
- the 240-byte door: `MAX_PAYLOAD_BYTES = 240` (`RankSync.lua:22`), enforced at
  enqueue (`:486-489`). VERIFIED.
- the `G` and `D` message kinds: `RankSync.lua:1345` (`kind == "G"`) and `:1377`
  (`kind == "D"`), and the `D;` frame is built at `:1202`. VERIFIED.

### 1.5 The saved-variable shapes — **HOLDS, with one additive key**

- `TacoTip.toc:9` -> `## SavedVariables: TacoTipConfig`. Exactly one saved variable
  for this add-on. VERIFIED.
- the shape is the flat `DEFAULTS` table in `options.lua:165-239`; `TT:GetDefaults()`
  (`options.lua:241`) hands out a shallow copy, `TT:ApplyConfigDefaults`
  (`options.lua:271`) fills every missing key, and `TT:SafeSanitizeConfig`
  (`options.lua:354`) repairs a hand-edited file on every load. VERIFIED.
- **drift vs HEAD:** the `DEFAULTS` key set grew from 67 to 68 — one key added,
  `scan = true` (`options.lua:235`), nothing removed. Additive and default-safe
  (the comment at `options.lua:230-234` states the library default is also
  "enabled"), but it IS a change to the saved-variable shape since the last commit.
  VERIFIED (recorded as finding **F5**, nit).

### 1.6 `CanInspect` is called with EXACTLY ONE argument — **HOLDS**

See §4 for the full per-branch table. Short form: the only call to the client's
global in the whole shipped tree is one argument. VERIFIED.

### 1.7 No invented translations — **HOLDS to the extent this lane can establish**

See §5. The key set is identical across all 11 locale files, no value is empty, no
key exists in only one locale. **UNKNOWN:** whether every translated *value* is
sourced from a real client string — the mirror is english-only FrameXML and no web
access was permitted in this lane, so no value could be checked against
wago.tools or a localised client page. See finding **F7**.

### 1.8 The inspect-frame guild guard stays installed — **HOLDS**

- `main.lua:4097-4122` `guardBlizzardInspectGuildFrame()` replaces
  `_G.InspectGuildFrame_Update` with a two-bucket `pcall` wrapper; the guild bucket
  is decided by the client's own data (`C_PaperDollInfo.GetInspectGuildInfo`,
  `main.lua:4080-4095`), not by matching an error string. VERIFIED.
- installed from `TT:InitInspectFrame()` (`main.lua:4125`), which is reached from the
  `ADDON_LOADED` handler for `Blizzard_InspectUI` (`main.lua:4991-4995`), from the
  add-on's own `ADDON_LOADED` (`main.lua:4981-4984`), from `INVENTORY_READY` /
  `TALENTS_READY` (`main.lua:5017-5020`) and from `TT:RefreshInspectFrame`
  (`main.lua:4213-4218`). Every path checks `InspectModelFrame and
  InspectPaperDollFrame` first. VERIFIED.
- on the classic family the global does not exist, so the guard is a no-op
  (`main.lua:4098-4099` returns false when `InspectGuildFrame_Update` is not a
  function). VERIFIED.

---

## 2. B2 — every `HookScript` / `SetScript` on a Blizzard frame

### 2.0 The engine rule, established from the client's own code — VERIFIED

`HookScript` raises `bad argument #2 to 'HookScript'` when the frame does not
declare that script. **Which scripts a frame "declares" is not the same as what its
XML `<Scripts>` block lists:** `OnShow` and `OnHide` are engine-default frame
scripts and are present on every frame, whether or not the frame's XML declares
them. Two pieces of Blizzard's own shipped code prove this:

1. **OnShow.** `origin/classic_era:Interface/AddOns/Blizzard_UIPanels_Game/Classic/SkillFrame.xml:129`
   is `<Frame name="SkillFrame" setAllPoints="true" enableMouse="true" parent="CharacterFrame" useParentLevel="true" id="4" hidden="true">`
   — with **no `<Scripts>` element at its own level** (the `<Scripts>` blocks at
   `:275`, `:283`, `:300` are at deeper indentation and belong to descendants) and
   no `inherits=` template. Yet
   `origin/classic_era:Interface/AddOns/Blizzard_PTRFeedback/Blizzard_PTRFeedback_Tooltips.lua:152`
   does `SkillFrame:HookScript("OnShow", UpdateSkillTooltips)`. The same file and
   line exist on `classic_anniversary` and `classic_titan`. VERIFIED.
2. **OnHide.** `origin/live:Interface/AddOns/Blizzard_PTRFeedback/Blizzard_PTRFeedback.lua:1`
   is `PTR_IssueReporter = CreateFrame("Frame", nil, GetAppropriateTopLevelParent())`
   — no template, no prior `SetScript`. Yet
   `origin/live:Interface/AddOns/Blizzard_PTRFeedback/Blizzard_PTRFeedback_Frames.lua:773`
   does `PTR_IssueReporter:HookScript("OnHide",function() surveyFrame:Hide() end)`.
   The same shape is on `forever`. VERIFIED.

The tooltip-specific scripts (`OnTooltipSetUnit`, `OnTooltipSetItem`,
`OnTooltipSetSpell`, `OnTooltipCleared`) are **not** defaults and must be declared.

### 2.1 `main.lua` — every `HookScript` site, per branch

| # | site | target | guard | can it raise? |
| :--- | :--- | :--- | :--- | :--- |
| 1 | `main.lua:3027` `frame:HookScript(scriptName, function(...) return runUntainted(handler, ...) end)` inside `hookTooltipScripts` | `GameTooltip` (unit, :3049), `GameTooltip`/`ShoppingTooltip1`/`ShoppingTooltip2`/`ItemRefTooltip` (item, :3295-3298), `GameTooltip` (spell, :3487) | **YES** — `main.lua:3020-3021` `if (frame and type(frame) == "table" and frame.HasScript and frame:HasScript(scriptName))` | **NO on all five.** The guard is exactly the check `HookScript` performs. |
| 2 | `main.lua:3415` `tooltipFrame:HookScript("OnTooltipCleared", function(tFrame) ... end)` | the ten tooltips at `main.lua:3456-3467` | **YES** — `main.lua:3414` `if (tooltipFrame:HasScript("OnTooltipCleared"))` | **NO on all five.** |
| 3 | `main.lua:3428` `tooltipFrame:HookScript("OnShow", function(tFrame, ...) ... end)` | same ten | **YES** — `main.lua:3427` `if (tooltipFrame:HasScript("OnShow"))` | **NO on all five.** (And `OnShow` is a default anyway — §2.0.) |
| 4 | `main.lua:3433` `tooltipFrame:HookScript("OnHide", function(tFrame) ... end)` | same ten | **YES** — `main.lua:3432` | **NO on all five.** |
| 5 | `main.lua:3800` `GameTooltipStatusBar:HookScript("OnHide", function() ... end)` | the tooltip's status bar | **partial** — `main.lua:3799` `if (GameTooltipStatusBar) then` (existence only, **no `HasScript`**) | **NO on all five**, because `OnHide` is an engine default (§2.0). The frame's XML declares no `OnHide`: classic `GameTooltipTemplate.xml:138-148` declares `<OnValueChanged method="OnValueChanged"/>` only; modern `GameTooltip.xml:15-21` declares `OnLoad`/`OnUpdate`/`OnValueChanged` only. |
| 6 | `main.lua:3931` `_G.CharacterFrame:HookScript("OnShow", function() ... end)` | `CharacterFrame` | **partial** — `main.lua:3930` `if (_G.CharacterFrame and _G.CharacterFrame.HookScript) then` (existence only) | **NO on all five.** `OnShow` is a default (§2.0), and the frame declares it anyway: classic_era `Blizzard_CharacterFrame/Vanilla/CharacterFrame.xml:256` `<OnShow function="CharacterFrame_OnShow"/>` (TBC `:218`, Wrath `:216`; identical on classic_anniversary and classic_titan); forever `Blizzard_UIPanels_Game/Mainline/CharacterFrame.xml:409` `<OnShow method="OnShow"/>`; live `Blizzard_UIPanels_Game/Mainline/CharacterFrame.xml:304` `<OnShow method="OnShow"/>`. |
| 7 | `main.lua:4184` `_G.InspectFrame:HookScript("OnShow", function() ... end)` | `InspectFrame` | **partial** — `main.lua:4183` `if (_G.InspectFrame and _G.InspectFrame.HookScript) then` | **NO on all five.** `OnShow` is a default, and the frame declares it: classic_era `Blizzard_InspectUI/Vanilla/Blizzard_InspectUI.xml:76` `<OnShow function="InspectFrame_OnShow"/>` (TBC `:102`; identical on classic_anniversary and classic_titan); live `Blizzard_InspectUI/Mainline/Blizzard_InspectUI.xml:4` defines the frame; forever the same file exists. |
| 8 | `main.lua:4201` `InspectFrame:HookScript("OnHide", function() ... end)` | `InspectFrame` | **NONE on `InspectFrame` itself** | **NO in practice on all five, but the guard is indirect.** `InspectFrame` and `InspectModelFrame` ship in the SAME LoadOnDemand addon — `Blizzard_InspectUI/.../Blizzard_InspectUI.xml` and `Blizzard_InspectUI/.../InspectPaperDollFrame.xml:114` (classic_era/anniversary/titan), `.../Mainline/InspectPaperDollFrame.xml:112` (live), `.../Mainline/InspectPaperDollFrame.xml:112` (forever) — and every path into `TT:InitInspectFrame()` checks `InspectModelFrame and InspectPaperDollFrame` first (`main.lua:4214`, `:4981`, `:4992`, `:5017`). Recorded as finding **F2** (nit). |

`Detours:ScriptHook(TT, GameTooltip, "OnShow", ...)` (`main.lua:5231`) and
`... "OnHide" ...` (`main.lua:5234`) reach `HookScript` through
`Libs/LibDetours-1.0/LibDetours-1.0.lua:169` `funcTable:HookScript(funcName, ...)`.
`OnShow`/`OnHide` are defaults -> **no raise on any branch**. VERIFIED.

### 2.2 What the classic / modern split actually is (the XML the code depends on)

**classic_era / classic_anniversary / classic_titan** — byte-identical
`Blizzard_SharedXML/Classic/GameTooltipTemplate.xml`:
- `:150-156` — the `GameTooltipTemplate` `<Scripts>` block declares `OnLoad`,
  **`OnHide`** (`:152`), `OnTooltipSetDefaultAnchor`, `OnTooltipAddMoney` and
  **`OnTooltipCleared`** (`:155`). It does **not** declare `OnTooltipSetUnit`,
  `OnTooltipSetItem` or `OnTooltipSetSpell`.
- `Blizzard_GameTooltip/Classic/GameTooltip.xml:13-35` — the real `GameTooltip`
  declares `<OnTooltipSetUnit function="GameTooltip_OnTooltipSetUnit" />` (`:22`),
  `<OnTooltipSetItem function="GameTooltip_OnTooltipSetItem" />` (`:23`),
  `<OnTooltipSetSpell function="GameTooltip_OnTooltipSetSpell" />` (`:24`),
  `<OnHide>` (`:25`), `<OnUpdate>` (`:33`).
- `Blizzard_GameTooltip/Classic/GameTooltip.xml:3` and `:8` — `ShoppingTooltip1`
  and `ShoppingTooltip2` declare **only** `<OnTooltipSetItem function="GameTooltip_OnTooltipSetShoppingItem" />`
  (`:5`, `:10`) plus `OnTooltipCleared` inherited from `ShoppingTooltipTemplate`
  (`GameTooltipTemplate.xml:212-215`).
- `Blizzard_UIPanels_Game/Classic/ItemRef.xml:5` — `ItemRefTooltip` inherits
  `GameTooltipTemplate`.

**forever / live** — `Blizzard_SharedXML/SharedTooltipTemplates.xml`:
- `:96-101` — `SharedTooltipTemplate` declares `OnLoad`, **`OnHide`** (`:98`),
  `OnTooltipSetDefaultAnchor` and **`OnTooltipCleared`** (`:100`). It declares
  **no** `OnTooltipSetUnit` / `OnTooltipSetItem` / `OnTooltipSetSpell`.
- `Blizzard_GameTooltip/Mainline/GameTooltip.xml:249` — the real `GameTooltip`
  inherits `GameTooltipTemplate`; its own `<Scripts>` (`:269-273`) declare `OnLoad`,
  **`OnShow`** (`:271`) and `OnUpdate`.
- `Blizzard_GameTooltip/Mainline/GameTooltip.xml:239-240` — `ShoppingTooltip1` /
  `ShoppingTooltip2` inherit `ShoppingTooltipTemplate` (`GameTooltip.xml:109`),
  which adds **no** tooltip-set script.

**Consequence:** `hookTooltipScripts("OnTooltipSetUnit", ...)`,
`("OnTooltipSetItem", ...)` and `("OnTooltipSetSpell", ...)` find a script on the
**classic three** and **not** on the modern pair — which is exactly why the
`HasScript` guard at `main.lua:3020-3021` is load-bearing, and why the
`/tacotip diag` fields `TT.HookedTooltipScripts.Unit/Item/Spell`
(`main.lua:3038-3042`, `:3291-3293`, `:3484-3487`) read `postcall`/`nil`
differently per client. VERIFIED per branch.

### 2.3 `options.lua` — **no `HookScript` at all**, and no `SetScript` on a Blizzard frame

`grep -n "HookScript" options.lua` -> **no hits**. Every `SetScript` in
`options.lua` targets an **add-on-created** frame: `optionsFrame` (`options.lua:820`
`CreateFrame("Frame", "TacoTipOptions")`), `optionsBootstrapFrame` (`:1068`), the
pages (`:825-827`), the media picker and its children (`:1654`, `:1685`, `:1689`),
the dropdown/editbox/slider controls (`:1865`, `:1948`, `:1993`), the panel scroll
frames (`:2171`, `:2440`, `:2456`), the checkbox/button helpers (`:1614`, `:1638`)
and the options page frames (`:3456`, `:3464`, `:2923`). **No Blizzard frame is
`SetScript`ed anywhere in `options.lua`.** VERIFIED.

`main.lua`'s `SetScript` sites are likewise all add-on frames: `TacoTipPowerBar`
(`:2862`), `TacoTipMouseAnchor` (`:3491`), the mover (`:3814`), the drag button
(`:5247`...), and the event frame `local f = CreateFrame("Frame")` (`:5062`). VERIFIED.

---

## 3. B3 — the containment, second pair of eyes

`main.lua:498-525` and `options.lua:26-44` are the two copies.

### 3.1 The mechanism — VERIFIED, no defect

```
main.lua:498      local secureCallFn = nil
main.lua:499      if (type(securecall) == "function") then
main.lua:510-514      local probeRan = false
                      local probeOk = pcall(securecall, function() probeRan = true end)
                      if (probeOk and probeRan) then secureCallFn = securecall end
main.lua:517      local function runUntainted(fn, ...)
main.lua:518-519     if (secureCallFn) then return secureCallFn(fn, ...) end
main.lua:524      return fn(...)
```

- **Argument forwarding:** `runUntainted` is a **vararg** function (`local function
  runUntainted(fn, ...)`, `main.lua:517`; `options.lua:39`), and both branches
  forward `...`. No argument is dropped at any of the 12 call sites. VERIFIED.
- **`securecall` forwards arguments** — proven by Blizzard's own three-argument call
  on **all five branches**:
  `securecall(self.UpdateDuration, self, self.timeLeft); -- Taint issue with SecondsToTimeAbbrev`
  (`Blizzard_BuffFrame/BuffFrame.lua`, present on classic_era, classic_anniversary,
  classic_titan, forever and live). VERIFIED.
- **`...` inside a NON-vararg inner function:** **not present anywhere.** Every
  `runUntainted(function(...) ... end)` payload is either a vararg function or a
  zero-arg function whose body uses only upvalues. The Lua 5.1 compile-error shape
  that the prior audit found in `TacoTip_Extras/Tooltips.lua` does **not** occur in
  the main add-on. VERIFIED.
- **Return values:** the only returns the callers use are the hook handlers', which
  the client discards for `OnShow`/`OnHide`/`OnTooltipSet*`. Nothing is lost that a
  caller reads. VERIFIED.
- **The probe:** `pcall(securecall, function() probeRan = true end)` — `probeRan` is
  an upvalue of the probe closure, so it is set only if `securecall` actually ran
  the function. `options.lua:32-36` is the same shape. VERIFIED.

### 3.2 The payload audit — **one defect class found (F1)**

| site | payload | own containment? |
| :--- | :--- | :--- |
| `main.lua:3028` `runUntainted(handler, ...)` | `handler` is `function(tooltip, ...) handleTooltipSetUnit(tooltip) end` (:3046) or `safeItemToolTipHook` (:3177-3179, `return safeCall(itemToolTipHook, self, ...)`) or `function(tooltip) return safeCall(clearTooltipVisuals, tooltip) end` (:3485-3487) | **YES** (through `safeCall`) |
| `main.lua:3418` `runUntainted(function() ... end)` (`OnTooltipCleared`) | `isUnitFramePeriodicUpdate(tFrame)` (:3419) and `cancelDelayedTooltip(tFrame)` (:3422) are **outside** any pcall; only `clearTooltipVisuals` is wrapped (:3423) | **PARTIAL** |
| `main.lua:3434` `runUntainted(function() ... end)` (`OnHide`) | same shape: `isUnitFramePeriodicUpdate` (:3435) and `cancelDelayedTooltip` (:3438) unwrapped; `clearTooltipVisuals` wrapped (:3441) | **PARTIAL** |
| `main.lua:3429` `runUntainted(safeCall, onTooltipShow, tFrame, ...)` | `safeCall` inside | **YES** |
| `main.lua:3740` `runUntainted(function() ... end)` (anchor post-hook) | explicit `pcall(onGameTooltipSetDefaultAnchor, tooltip, parent)` with a counter (:3741-3746) | **YES** |
| `main.lua:3804` `runUntainted(function() ... end)` (status bar `OnHide`) | `if (TacoTipPowerBar) then TacoTipPowerBar:Hide() end` (:3805-3807) and `stopPowerBarTicker()` (:3808), which itself nil-guards (:578-586) | **effectively yes** |
| `main.lua:3934` (`CharacterFrame:OnShow`) | `pcall(TT.RefreshCharacterFrame, TT)` with a counter (:3942-3947) | **YES** |
| `main.lua:4187` (`InspectFrame:OnShow`) | `pcall(TT.RefreshInspectFrame, TT)` with a counter (:4192-4197) | **YES** |
| `main.lua:4202` (`InspectFrame:OnHide`) | `InspectGearScore:Hide()` / `InspectAvgItemLvl:Hide()` — both are globals created earlier in the same function (:4126, :4146), so they exist | **nil-safe, but not pcall'd** |
| `main.lua:4936` `runUntainted(safeCall, function() ... end)` (`GameTooltip.FadeOut` post-hook) | `safeCall` inside | **YES** |
| `main.lua:5232`, `:5235` | `runUntainted(safeCall, onMoverGameTooltipShow/Hide, tooltipFrame, ...)` | **YES** |
| `options.lua:576` `runUntainted(safeCall, function() ... end)` (`GameTooltip.FadeOut` post-hook) | `safeCall` inside | **YES** |
| `options.lua:1558` `runUntainted(safeCall, function() ... end)` (hover tooltip) | `safeCall` inside | **YES** |
| `options.lua:1583` `runUntainted(safeCall, function() GameTooltip:Hide() end)` | `safeCall` inside | **YES** |

**F1 (should-fix).** `main.lua:3418` and `main.lua:3434`: two of the containment
payloads are **not** fully self-contained. `securecall` swallows a raise and returns
nil, so a raise inside `isUnitFramePeriodicUpdate(tFrame)` or
`cancelDelayedTooltip(tFrame)` would be **silent** — no `geterrorhandler()` line, no
counter, nothing in `/tacotip diag`. The same raise on the **fallback** path
(`main.lua:524` `return fn(...)`, taken when the probe did not arm the containment)
would **propagate** into the client's script chain. The comment at
`main.lua:521-523` — "Every call site still has its own error containment, so the
fallback degrades to 'the taint guard is missing', never to 'the add-on raises'" —
is true for the other sites but **not** for these two. The prior audit's §10.4
statement that "every other containment site already had its own containment" does
not cover these two. VERIFIED.

The raise risk inside the two helpers is low but not zero: `isUnitFramePeriodicUpdate`
(`main.lua:3388-3408`) calls `tooltip:GetOwner()`, `owner.UpdateTooltip`,
`UnitExists` and `UnitGUID`; `cancelDelayedTooltip` -> `cancelTooltipTimer`
(`main.lua:356-363`) calls `getTooltipState(tooltip)` and `timer:Cancel()`.

### 3.3 The no-replaced-globals rule — HOLDS

`Detours:DetourHook` is the only mechanism in the tree that replaces a global
(`Libs/LibDetours-1.0/LibDetours-1.0.lua:134` `rawset(_G, funcName, func)`). The
shipped tree makes **no** `DetourHook` call on a global:

| call | site | target | verdict |
| :--- | :--- | :--- | :--- |
| `Detours:DetourHook(lib, errors, "AddMessage", inspectErrorSink)` | `LibForeverInspector.lua:5027` | the `UIErrorsFrame` **table field** | not a global; classic_era only (`:5022` `if (not isClassic) then return false end`) |
| `Detours:DetourHook(lib, sound, "PlayVocalErrorSound", inspectVoiceSink)` | `LibForeverInspector.lua:5030` | the `C_Sound` **table field** | not a global; classic_era only |
| `Detours:DetourHook(lib, "PlayVocalErrorSoundID", inspectVoiceSink)` | `LibForeverInspector.lua:5035` | **global** | replaced — classic_era only; never called by the game menu |
| `Detours:DetourHook(lib, "GetGameMessageInfo", inspectGameMessageInfoSink)` | `LibForeverInspector.lua:5042` | **global** | replaced — classic_era only; the client calls it from `UIErrorsMixin:TryDisplayMessage`, never from the game menu |

`PlaySound` is **not** replaced anywhere — the carrier the prior audit identified is
gone. VERIFIED. `Detours:SecureHook` (`LibDetours:1.0:73-80`) uses `hooksecurefunc`
and replaces nothing. `main.lua:4925` and `options.lua:568` use only that form.

`rawset(_G, ...)` elsewhere in the shipped tree: `main.lua:15`, `options.lua:117`,
`gearscore.lua:20`, `textures.lua:5` (the add-on's own namespace), `main.lua:4101-4102`
(the guild guard), and `options.lua:700` / `gearscore.lua:226` (`SlashCmdList`, and
**only** when `rawget(_G, "SlashCmdList")` is nil — the client's own proxy is never
replaced). VERIFIED.

---

## 4. B4 — the `CanInspect` call, per branch

### 4.1 Every call site in the shipped tree

| file:line | code | arguments |
| :--- | :--- | :--- |
| `Libs/LibForeverInspector/LibForeverInspector.lua:5073` | `local ok, allowed = pcall(api, unit)` where `api = _G.CanInspect` (`:5067`) | **ONE** |
| `Libs/LibForeverInspector/LibForeverInspector.lua:5090` | `local ok, allowed = pcall(api, unit, INSPECT_INTERACT_DISTANCE_INDEX)` where `api = _G.CheckInteractDistance` (`:5084`) | two — correct for `CheckInteractDistance` |

`grep -rn "CanInspect" main.lua options.lua gearscore.lua pawn.lua textures.lua`
-> **no hits at all**. The add-on's own product files never touch `CanInspect`.

`lib:CanInspect(unit)` (`LibForeverInspector.lua:4078`) is the **library's own
method**, not the client's global; every internal call site (`:5211`, `:5390`,
`:5413`, `:5449`, `:5469`, `:5482`, `:5623`) goes through it.

**VERIFIED: no call in the shipped tree passes a second argument to `CanInspect`.**

### 4.2 The client's own call sites, per branch

| branch | client call sites (whole-tree sweep of `Interface/`) |
| :--- | :--- |
| classic_era | `Blizzard_InspectUI/Vanilla/Blizzard_InspectUI.lua:5` `if ( CanInspect(unit, true) ) then`; `Blizzard_InspectUI/TBC/Blizzard_InspectUI.lua:10` `if ( CanInspect(unit, true) ) then` |
| classic_anniversary | same two files, same lines |
| classic_titan | same two files, same lines |
| forever | `Blizzard_InspectUI/Mainline/Blizzard_InspectUI.lua:10` `if ( CanInspect(unit, true) ) then`; `Blizzard_InspectUI/Camelot/Blizzard_InspectUI.lua:43` `if CanInspect(unit, true) then`; and the ONE-argument form `Blizzard_UnitPopupShared/UnitPopupSharedButtonMixins.lua:293` and `:318` `return not UnitIsDeadOrGhost("player") and CanInspect(contextData.unit);` |
| live | `Blizzard_InspectUI/Mainline/Blizzard_InspectUI.lua:10`, `Blizzard_InspectUI/TBC/Blizzard_InspectUI.lua:10`, `Blizzard_InspectUI/Vanilla/Blizzard_InspectUI.lua:5` (all two-argument), plus the commented-out one-argument form at `Mainline/Blizzard_InspectUI.lua:55` |

So the client itself uses **two** arguments in `InspectFrame_Show` on every branch
and **one** argument in the unit-popup path. The add-on uses one. VERIFIED per branch.

### 4.3 The API-doc entry, per branch

`Interface/AddOns/Blizzard_APIDocumentationGenerated/PlayerScriptDocumentation.lua`:

- classic_era / classic_anniversary / classic_titan — `:53-66`:
  ```
  Name = "CanInspect",
  Type = "Function",
  Arguments = { { Name = "targetGUID", Type = "UnitToken", Nilable = false }, },
  Returns  = { { Name = "result", Type = "bool", Nilable = false }, },
  ```
- forever / live — `:54-68`: the same, plus `SecretArguments = "AllowedWhenUntainted",`.

**One documented argument on all five branches.** VERIFIED. The add-on honours the
invariant and the client's own `CanInspect(unit, true)` is the shape the add-on
deliberately does not use.

---

## 5. B5 — the locale parity

11 files: `Locale/{deDE,enUS,esES,esMX,frFR,itIT,koKR,ptBR,ruRU,zhCN,zhTW}.lua`.

### 5.1 Key set, count, order

| file | keys | same set as enUS? | same order as enUS? |
| :--- | :--- | :--- | :--- |
| enUS | 239 | — | — |
| deDE / esES / esMX / frFR / itIT / koKR / ptBR / ruRU | 239 | **yes** (no key missing, no key extra) | **NO** — 107-key common prefix, the remaining 133 are reordered as a block |
| zhCN / zhTW | 239 | **yes** | **NO** — 80-key common prefix, the remaining 160 are reordered as a block |

The reorder is a **block move**, not a per-key shuffle: in the eight Latin-script
locales the `OPTIONS_SECTION_*` group plus the `FORMAT_GUILD_RANK_1` /
`CHARACTER_FRAME_*` / `INSPECT_FRAME_*` block moves to the **front** of the reordered
tail; in zhCN/zhTW the same block moves to the **back**. The **key set and the count
are identical everywhere** (239 = 239). VERIFIED.

**F4 (nit).** The "same order" property does not hold for any non-English locale,
and nothing in the repo pins it. The loader is a table lookup
(`_G.TACOTIP_LOCALES["<locale>"] = L` at the end of each file; `main.lua:35`
`local L = _G.TACOTIP_LOCALE`), so the order is functionally irrelevant — but the
claim "same key set, same order, same count" is only true for the first and the
last.

### 5.2 Empty values and untranslated copies

- **Empty-string values: none**, in any of the 11 files. VERIFIED.
- **Keys present in only one locale: none.** VERIFIED.
- Values byte-identical to `enUS` in a non-English locale, after excluding numbers,
  font names and format strings: **4 in deDE, 4 in frFR, 2 in itIT, 1 each in
  esES / esMX / ptBR, 0 in koKR / ruRU / zhCN / zhTW**:
  - `COMPACT` = "COMPACT" and `MINI` = "MINI" — the add-on's own mode names, shown
    verbatim in the dropdown (`options.lua:2259`, `:2261`). Legitimate, not a
    translation defect.
  - `Talents` = "Talents" (frFR), `Style` = "Style" (deDE, frFR), `Realm` = "Realm"
    (deDE) — these are words that are spelled the same in those languages, but
    **that has not been sourced** (see F7).
  - `OPTIONS_PAGE_TOOLTIPS` = "Tooltips" (deDE) — a page label. Same caveat.
- Every other string value in all ten non-English files differs from `enUS`.

**F7 (UNKNOWN, needs a sourced check).** No translated value in this lane could be
checked against a client string source: the mirror carries english-only FrameXML
with no GlobalStrings file on any branch (the add-on's own note at
`LibForeverInspector.lua:4731-4732` says the same), and this lane had no web
access. Whether the 8 same-spelling values above are the *client's* wording is
**UNKNOWN**; whether the ~2000 other values are sourced translations is **UNKNOWN**.

---

## 6. B6 — the `.toc` and the package

### 6.1 `TacoTip.toc`

```
:1  ## Interface: 11509, 20506, 38002, 16001, 120105
:2  ## Version: 0.8.4
:9  ## SavedVariables: TacoTipConfig
```

- The `## Interface` band lists **exactly the five supported builds**, and the
  live build is `120105` (the diff vs HEAD shows it was `120100` and is now
  `120105`). VERIFIED.
- `## SavedVariables: TacoTipConfig` — one saved variable, matching §1.5. VERIFIED.
- The file list is `Libs\LibStub\LibStub.lua`, `Libs\CallbackHandler-1.0\CallbackHandler-1.0.lua`,
  `Libs\LibDetours-1.0\LibDetours-1.0.lua`, `Libs\LibForeverInspector\LibForeverInspector.lua`,
  the 11 `Locale\*.lua`, then `gearscore.lua`, `pawn.lua`, `textures.lua`,
  `options.lua`, `main.lua`.

**Every listed file exists** — checked one by one against the working tree. VERIFIED.
**No listed file is missing.** Nothing in the toc points at a file that is not there.

### 6.2 The package

`bash Tools/verify_release.sh --worktree` -> **PASS**, 27 files:

```
CHANGELOG.md  LICENSE  README.md  THIRD_PARTY_NOTICES.md  TacoTip.toc
tt.tga
gearscore.lua  main.lua  options.lua  pawn.lua  textures.lua
Libs/CallbackHandler-1.0/CallbackHandler-1.0.lua
Libs/CallbackHandler-1.0/CallbackHandler-1.0.xml
Libs/LibDetours-1.0/LibDetours-1.0.lua
Libs/LibForeverInspector/LibForeverInspector.lua
Libs/LibStub/LibStub.lua
Locale/{deDE,enUS,esES,esMX,frFR,itIT,koKR,ptBR,ruRU,zhCN,zhTW}.lua
```

The verifier's own four checks pass: one `.toc`; no `desks/ bench/ docs/ Tests/
OLD/ TacoTip_Extras/ Tools/`; no `hands-up.md` / `workshop.md`; runtime files only.
VERIFIED.

Files present in the **working tree** but deliberately NOT in the package, and why:
- `Libs/LibDetours-1.0/LibDetours-1.0.toc`, `Libs/LibStub/LibStub.toc` — tracked,
  export-ignored by `.gitattributes` ("Library `.toc` metadata … these would be
  extra `.toc` files with nothing to load"). Correct: the package has exactly one
  `.toc`.
- `Libs/CallbackHandler-1.0/CallbackHandler-1.0.xml` — **IS** in the package
  (harmless: it is a template description with no Lua).
- `Libs/LibDataBroker-1.1/`, `Libs/LibDBIcon-1.0/` — **UNTRACKED** directories in
  the working tree, export-ignored by `.gitattributes`, not loaded by `TacoTip.toc`,
  and their licence provenance is explicitly unverified in the `.gitattributes`
  comment. They are not in the `git archive` package.

**F6 (nit).** The two vendored libraries are excluded from the `git archive`
package, but they **are** sitting in the working tree. A release packed by zipping
the folder rather than by `git archive` would ship two libraries that the toc does
not load and whose licence provenance is unverified. The verifier only checks the
archive.

---

## 7. B7 — the client APIs the add-on calls that the mirror may not carry

### 7.1 Method

The generated API docs of all five branches were extracted
(`Interface/AddOns/Blizzard_APIDocumentationGenerated/`, 2864 files) and indexed by
`Name = "..."` plus the enclosing `Namespace`. Every uppercase global call and
every `_G.X` / `_G["X"]` access in `main.lua`, `options.lua`, `gearscore.lua`,
`pawn.lua`, `textures.lua` and `Libs/LibForeverInspector/LibForeverInspector.lua`
was then checked against that index, **and** against a whole-tree sweep of the
branch's `Interface/` directory (`git grep -w -l <name> origin/<branch> -- Interface/`),
because an absence from the generated docs is **not** an absence on the classic
branches (see 7.6).

### 7.2 Globals the add-on calls that are absent from the generated API docs on EVERY branch

| name | shipped-tree use | whole-tree sweep | guard |
| :--- | :--- | :--- | :--- |
| `GetActiveSpecGroupFor` | `LibForeverInspector.lua:3245`, `:3821`, `:3827`, `:5986` | 0 hits on all five branches | **It is the library's OWN local function** (`local function GetActiveSpecGroupFor(isInspect)`, `:3245`), not a client API. No issue. |
| `InterfaceOptionsFrame_Show` | `options.lua:1130` | 0 hits on all five branches | **Guarded and pcall'd**: `options.lua:1129` `if (_G.InterfaceOptionsFrame_Show) then` / `:1130` `pcall(_G.InterfaceOptionsFrame_Show)`. No raise. |
| `GetNumTalentTabs` | resolved at call time by `getNumTalentTabs()` (`LibForeverInspector.lua:62-64`) | present on the classic three (3 files each), **0 on forever and live** | **Guarded by construction**: the helper returns `_G.GetNumTalentTabs` and every caller tests it (`LibForeverInspector.lua:3823` `elseif (getNumTalentTabs() or _G.GetNumTalents) then`, `:262` `talentTabs = (getNumTalentTabs() ~= nil) and true or false`). The modern pair takes the `C_SpecializationInfo` branch instead. No raise. |
| `GameTooltip_SetDefaultAnchor` | `main.lua:3725-3726` | 47/47/47/38/28 files | **Guarded**: `main.lua:3725` `if (type(_G.GameTooltip_SetDefaultAnchor) == "function") then`. No raise. |

### 7.3 Namespace members that are not in the classic generated docs

| member | classic three | modern pair | the add-on's guard |
| :--- | :--- | :--- | :--- |
| `C_Item.GetItemLinkByGUID` | **absent from the classic docs — but the API EXISTS on Classic Era**: `origin/classic_era:Interface/AddOns/Blizzard_SharedXMLGame/Tooltip/TooltipUtil.lua:14` `hyperlink = C_Item.GetItemLinkByGUID(tooltipData.guid);` (Blizzard calls it unguarded) | documented (`ItemDocumentation.lua`) | `main.lua:3066` `if (data.guid and C_Item and C_Item.GetItemLinkByGUID) then` — **guarded**, and the arm is skipped on classic. See **F3**. |
| `C_SpecializationInfo.GetClassIDFromSpecID` | **genuinely absent** (0 whole-tree hits on classic_era / classic_anniversary / classic_titan) | present (`origin/live:.../SpecializationInfoDocumentation.lua:66`, and called at `origin/live:.../Blizzard_PlayerSpellsFrame.lua:242`) | `LibForeverInspector.lua:3342` `if (C_SpecializationInfo.GetClassIDFromSpecID) then` — **guarded**; and the enclosing function returns early at `:3298` if `C_SpecializationInfo` itself is missing, so the namespace is never indexed while nil. No raise. |
| `C_SpecializationInfo.GetInspectSpecialization` | not in the classic docs | documented | `LibForeverInspector.lua:261` (capability snapshot) and `:3328` `and C_SpecializationInfo.GetInspectSpecialization` — **guarded**, and the namespace is non-nil by `:3298`. No raise. |

### 7.4 The globals that ARE in the docs on the modern pair but NOT on the classic three

This is a **documentation-coverage artefact, not an API difference**. The classic
branches' generated docs do not document `CreateFrame`, `UnitRace`,
`UnitIsDeadOrGhost`, `GetBuildInfo`, `IsShiftKeyDown`, `IsModifierKeyDown`,
`GetScreenWidth` — all of which obviously exist on Classic Era (Blizzard's own
code calls them on every branch). The classic doc set is 18 358 names against
23 859 (forever) and 23 277 (live). **This must not be read as an absence.**

### 7.5 The verdict

**Every Blizzard global and namespace member the shipped tree calls is present in
the client's whole `Interface/` tree on all five branches, or is guarded by a
`type(...) == "function"` / `and <member>` test, or is the add-on's own local
function. There is no unguarded call to a client API the mirror lacks.** VERIFIED
per branch, by the method in 7.1.

Two spots where the **guard is the only thing standing between the add-on and a
raise** and are worth naming:
- `LibForeverInspector.lua:3342` and `:3348` index `C_SpecializationInfo` without a
  local nil-check. They are safe **only** because `getModernSpecData` returns at
  `:3298` when the namespace is missing. A future edit that moves either line out
  of that function would raise on the classic three. VERIFIED (nit, not reported
  as a separate finding — it is inside a guarded function today).
- `options.lua:1130` `_G.InterfaceOptionsFrame_Show` is guarded and pcall'd. VERIFIED.

### 7.6 A METHOD correction to the prior audit's standing advice

`bench/audits/2026-10-21-quit-taint-carrier.md` §11.3 and `workshop.md`'s absence
rule both lean on "the generated api docs". On the **classic three** that source is
demonstrably incomplete: `CreateFrame`, `UnitRace`, `UnitIsDeadOrGhost`,
`GetBuildInfo`, `IsShiftKeyDown` and `C_Item.GetItemLinkByGUID` are all absent from
`origin/classic_era:Interface/AddOns/Blizzard_APIDocumentationGenerated/` and all
present in the client's own `Interface/` tree (for `C_Item.GetItemLinkByGUID`,
Blizzard's own unguarded call is
`origin/classic_era:Interface/AddOns/Blizzard_SharedXMLGame/Tooltip/TooltipUtil.lua:14`).
**On the classic branches an absence claim needs the whole-tree sweep; the
generated docs alone would produce a false defect report.** VERIFIED.

### 7.7 The remaining, separate risk: the mirror's age

The mirror is a **FrameXML mirror** — no engine code, and no GlobalStrings. A
client API that exists only in the engine's C++ and was added to the shipping
build after the mirror's snapshot would not appear anywhere in it. The mirror's
`live` branch is the only evidence for the 120105 build and it carries no
`GlobalStrings`. **UNKNOWN:** whether the mirror's `live` snapshot is the shipping
120105 build. Every "exists" claim in this artifact is a claim about the mirror.

---

## 8. Findings

| id | severity | label | finding |
| :--- | :--- | :--- | :--- |
| **F1** | **should-fix** | VERIFIED | `main.lua:3418` and `main.lua:3434`: the `OnTooltipCleared` / `OnHide` containment payloads call `isUnitFramePeriodicUpdate(tFrame)` and `cancelDelayedTooltip(tFrame)` outside any `pcall`/`safeCall`. `securecall` swallows a raise there silently, while the no-`securecall` fallback path (`main.lua:524`) propagates it — the two paths behave differently, and the comment at `main.lua:521-523` overstates the guarantee. |
| **F2** | nit | VERIFIED | `main.lua:4201` `InspectFrame:HookScript("OnHide", …)` has no existence guard on `InspectFrame`, unlike the sibling site at `main.lua:4183`. It is safe today only because `InspectFrame` and `InspectModelFrame` ship in the same LoadOnDemand addon and every entry point checks `InspectModelFrame`/`InspectPaperDollFrame` first (`main.lua:4214`, `:4981`, `:4992`, `:5017`). |
| **F3** | nit | VERIFIED | `main.lua:3064-3065`'s comment states "GetItemLinkByGUID is documented only on Forever and Retail; on the Classic branches this whole arm is skipped." The API **exists** on Classic Era — Blizzard calls it unguarded at `origin/classic_era:Interface/AddOns/Blizzard_SharedXMLGame/Tooltip/TooltipUtil.lua:14`. The behaviour (skipping it on classic) is conservative and harmless; the stated reason is wrong. |
| **F4** | nit | VERIFIED | The ten non-English locale files carry the same 239-key set but in a **different order** from `enUS.lua` (a block reorder; 107/80-key common prefix). Nothing pins the order and nothing depends on it. |
| **F5** | nit | VERIFIED | `options.lua:235` adds a new saved-variable key `scan = true` to the `TacoTipConfig` `DEFAULTS` table (68 keys vs 67 at HEAD; nothing removed). Additive and default-safe, but it is a change to the saved-variable shape since the last commit. |
| **F6** | nit | VERIFIED | `Libs/LibDataBroker-1.1/` and `Libs/LibDBIcon-1.0/` are UNTRACKED directories in the working tree. They are excluded from the `git archive` package (`.gitattributes` export-ignore, and the verifier confirms 27 files) and are not loaded by `TacoTip.toc`, but a release zipped from the folder would ship them, and `.gitattributes` records that their licence provenance is unverified. |
| **F7** | nit | UNKNOWN | The provenance of the translated locale **values** could not be established in this lane: the mirror carries english-only FrameXML with no GlobalStrings on any branch, and no web access was permitted. 8 same-spelling values in non-English locales (`COMPACT`, `MINI` x10 — these are the add-on's own mode names; `Talents` frFR; `Style` deDE + frFR; `Realm` deDE; `OPTIONS_PAGE_TOOLTIPS` deDE) need a sourced check against the client. |
| **F8** | nit (method) | VERIFIED | The classic branches' generated API docs are a smaller, demonstrably incomplete set: `CreateFrame`, `UnitRace`, `UnitIsDeadOrGhost`, `GetBuildInfo`, `IsShiftKeyDown` and `C_Item.GetItemLinkByGUID` are absent from them and present in the client's own tree. On the classic branches, "absent from the generated API docs" must not be reported as an absence. |

**No blocking finding.** The tree passes `bash Tests/harness/run_all.sh` (71/71),
`luacheck .` (0 warnings / 0 errors in 88 files) and
`bash Tools/verify_release.sh --worktree` (PASS, 27 files) as it stands.

---

## 9. The eight invariant verdicts, one line each

1. **Classic-era inspect range gate — HOLDS.** `NEARBY_ASK_YARDS = isClassic and 20 or 40` (`LibForeverInspector.lua:484`) and `INSPECT_INTERACT_DISTANCE_INDEX = 1` (`:466`) are byte-identical to HEAD; distance-first ordering (`:4111-4143`, `:4551-4560`), the probe guard (`:5063-5094`), the learned ceiling (`:4502-4509`) and every timing constant (`:4039`, `:4052`, `:4053`, `:4357`, `:4727`) are unchanged.
2. **Gearscore formula — HOLDS.** The `SlotMOD` table is md5-identical to HEAD; `ITEM_BAND_SCALE = 11.25`, `Scale`/`QualityScale` (`gearscore.lua:504`, `:520-530`), the A/B/C tables, the hunter factor `5.3224` (`:621`, `:779`) and titan grip `0.5` (`:668`, `:747`, `:752`, `:755`) are all unchanged; the file's numeric-literal multiset differs from HEAD only by the explicit `BRACKET_SIZE = 1000` and two literals in a new error counter.
3. **Retail bracket — HOLDS at the shared 1000.** `BRACKET_SIZE = 1000` (`gearscore.lua:382`); Classic 200 (`:385`), TBC 400 (`:387`), Forever 200 (`:389`), Unknown 1000 (`:396`); retail and Titanforge both fall through to the 1000 default and the Retail-only special case is absent.
4. **Wire format — HOLDS.** `WIRE_VERSION = "2"` (`TacoTip_Extras/RankSync.lua:175`), record head `"R"` + version (`:187-188`), `RECORD_FIELDS = 13` (`:212`), `MAX_PAYLOAD_BYTES = 240` (`:22`) enforced at enqueue (`:486`), `G`/`D` kinds (`:1345`, `:1377`, `:1202`). It lives in the companion add-on, not in this package.
5. **Saved-variable shapes — HOLDS, with one additive key.** `## SavedVariables: TacoTipConfig` (`TacoTip.toc:9`); the flat `DEFAULTS` table (`options.lua:165-239`) is filled by `ApplyConfigDefaults` (`:271`) and repaired by `SafeSanitizeConfig` (`:354`); one key added since HEAD (`scan = true`, `:235`), none removed.
6. **`CanInspect` is called with EXACTLY ONE argument — HOLDS.** The only call to the client's global is `pcall(api, unit)` (`LibForeverInspector.lua:5073`); no product file mentions `CanInspect`; the API is documented with one argument on all five branches (`PlayerScriptDocumentation.lua:54` classic / `:55` modern).
7. **No invented translations — HOLDS to the extent this lane can establish.** All 11 locale files carry the same 239-key set, no empty value, no key in only one locale, and only 8 same-spelling values in non-English files (of which 10 are the add-on's own `COMPACT`/`MINI` mode names). The **sourcing** of the values is UNKNOWN (F7).
8. **The inspect-frame guild guard stays installed — HOLDS.** `guardBlizzardInspectGuildFrame()` (`main.lua:4097-4122`) is called from `TT:InitInspectFrame()` (`:4125`), which is reached from the `Blizzard_InspectUI` `ADDON_LOADED` handler (`:4991-4995`), the add-on's own `ADDON_LOADED` (`:4981-4984`), `INVENTORY_READY`/`TALENTS_READY` (`:5017-5020`) and `TT:RefreshInspectFrame` (`:4213-4218`); it is a no-op on the classic family, where the global does not exist.

---

## 10. B2 per branch — which hook sites can raise

**No `HookScript` site in `main.lua` and no `SetScript` site in `main.lua` or
`options.lua` can raise on ANY of the five branches.** The three tooltip-specific
hooks are behind a `HasScript` guard; the remaining five hook `OnShow`/`OnHide`,
which are engine-default frame scripts (§2.0) and are also declared in the client's
own XML.

| site | classic_era | classic_anniversary | classic_titan | forever | live |
| :--- | :--- | :--- | :--- | :--- | :--- |
| `main.lua:3027` `HookScript(scriptName)` (OnTooltipSetUnit / OnTooltipSetItem / OnTooltipSetSpell) | guarded (`:3020-3021`) | guarded | guarded | guarded | guarded |
| `main.lua:3415` `HookScript("OnTooltipCleared")` | guarded (`:3414`) | guarded | guarded | guarded | guarded |
| `main.lua:3428` `HookScript("OnShow")` | guarded (`:3427`) | guarded | guarded | guarded | guarded |
| `main.lua:3433` `HookScript("OnHide")` | guarded (`:3432`) | guarded | guarded | guarded | guarded |
| `main.lua:3800` `GameTooltipStatusBar:HookScript("OnHide")` | no raise (OnHide default) | no raise | no raise | no raise | no raise |
| `main.lua:3931` `CharacterFrame:HookScript("OnShow")` | no raise (OnShow default; declared at `CharacterFrame.xml:256`) | no raise (`:256`) | no raise (`:216`) | no raise (`Mainline/CharacterFrame.xml:409`) | no raise (`:304`) |
| `main.lua:4184` `InspectFrame:HookScript("OnShow")` | no raise (OnShow default; declared at `Vanilla/Blizzard_InspectUI.xml:76`) | no raise | no raise | no raise | no raise |
| `main.lua:4201` `InspectFrame:HookScript("OnHide")` | no raise (guard is indirect — F2) | no raise | no raise | no raise | no raise |
| `main.lua:5231`/`:5234` `Detours:ScriptHook(GameTooltip, "OnShow"/"OnHide")` | no raise (OnShow/OnHide default) | no raise | no raise | no raise | no raise |
| every `SetScript` in `main.lua` (`:2862`, `:3498`, `:3824`-`:3835`, `:5063`, `:5247`-`:5279`) | add-on frames only | " | " | " | " |
| every `SetScript` in `options.lua` (32 handler installs; 38 `SetScript` lines in all) | add-on frames only | " | " | " | " |

---

## 11. What this lane could NOT establish

1. **The taint-propagation rule itself** is engine-side; the mirror has no engine
   code. Everything above about `securecall` being a taint boundary rests on
   Blizzard's own use of it. **ASSUMED** (unchanged from the prior audit).
2. **Whether the mirror's `live` branch is the shipping 120105 build.** The
   mirror's `live` is the only evidence for that build and it carries no
   `GlobalStrings`; a client API added after the snapshot would be invisible to
   every check in §7. **UNKNOWN.**
3. **The provenance of every translated locale value** (F7). No web access was
   permitted and the mirror is english-only. **UNKNOWN.**
4. **Whether the ten non-English locales' ORDER was deliberate** (F4). Nothing in
   the repo says. **UNKNOWN.**
5. **Whether the four non-Classic-Era clients behave like the mirror says.** Only
   Classic Era has been observed in game by the operator. Every other client claim
   here is a claim about the mirror. **UNKNOWN** (behaviourally).
6. **The `...`-in-a-non-vararg-function check was done by reading, not by a Lua
   5.1 compiler.** The main add-on's harness does load the files under three
   interpreters (`Tests/harness/run_all.sh`, 71/71 green), which is strong
   evidence the files compile, but the check itself was a read of every
   `runUntainted` payload. **VERIFIED** for the payloads; the harness covers the
   compile.
7. **The `TacoTip_Extras` package was not swept** — only the wire format was
   read, because it is one of the eight listed invariants and it lives there.

---

## 12. Validation bar

| # | check | result |
| :--- | :--- | :--- |
| 1 | `git -C /home/sam/wow-ui-source status --porcelain` unchanged by this work | **PASS** — same three entries as the baseline taken before any command in this lane (`?? .vscode/`, `?? SKILL.md`, `?? reference/`). |
| 2 | `git -C /home/sam/TacoTip-Gearscore-TBC status --short` shows no change to any product file | **PASS** — the only entries this lane added are `desks/main-publish-sweep-2026-10-21/` and this artifact. Every product file's mtime predates the lane (latest: `main.lua` 09:21:31, lane opened ~10:15): `main.lua`, `options.lua`, `gearscore.lua`, `pawn.lua`, `textures.lua`, `TacoTip.toc`, `Libs/LibForeverInspector/LibForeverInspector.lua` — all untouched. The pre-existing modifications to those files were present before this lane (baseline captured first) and are unchanged by it. **Note:** two bench artifacts written by *other* desks appeared during this lane and are not mine — `bench/audits/2026-10-21-extras-publish-review.md` (desk `extras-publish-review-2026-10-21`, 10:32:19) and `bench/audits/2026-10-21-publish-gate-verification.md` (desk `quit-taint-fix`, 10:24:22). Neither is a product file. |
| 3 | every `path:line` cited came from a command run in this lane | **PASS** |
| 4 | every client claim names its branch and carries an evidence label | **PASS** — §10 is per branch; every table in §7 is per branch; UNKNOWN items are listed in §11. |

**Tree state at hand-off:** `bash Tests/harness/run_all.sh` -> 71/71 passed ·
`luacheck .` -> 0 warnings / 0 errors in 88 files ·
`bash Tools/verify_release.sh --worktree` -> PASS (27 files).
