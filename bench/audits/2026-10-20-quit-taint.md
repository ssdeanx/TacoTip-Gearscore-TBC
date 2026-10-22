# The quit taint — why logging out is blocked on Classic Era

- **desk:** `quit-taint` · **date:** 2026-10-20 · **run_id:** `quittaint`
- **kind:** client-source analysis + taint inventory. **No product file was edited.**
- **supersedes:** nothing on the bench covers this. It **corrects two standing claims**
  (see "Corrections to standing knowledge" below): `workshop.md`'s bullet
  *"`GameTooltip.FadeOut` exists only on live and forever"*, and the brief's
  framing that `options.lua:483-506` / `main.lua:4792-4807` "claim all five"
  — those two repo comments are **right**; `workshop.md` is **wrong**.
- **evidence labels:** VERIFIED / ASSUMED / UNKNOWN, per `CAIRN.md`.
- **method:** `git -C /home/sam/wow-ui-source show origin/<branch>:<path>` (read-only)
  and read/grep of this repo. No web.

---

## 1. What the operator reported, and what the error already proves

> 3x `[ADDON_ACTION_FORBIDDEN] AddOn 'TacoTip' tried to call the protected function 'UNKNOWN()'.`
> `[!BugGrabber/BugGrabber.lua]:554` → `:538` → `[C]: ?` → `[C]: ?` →
> `[Blizzard_GameMenu/Shared/GameMenuFrame.lua]:69: in function <...GameMenuFrame.lua:66>`

Read bottom-up, that is: the closure defined at **GameMenuFrame.lua:66** was
executing **line 69**, and the call it made was refused by the engine's
protected-function guard (the two `[C]` frames).

**VERIFIED** — the line numbers in the error match `origin/classic_era`
(and `origin/classic_anniversary`, byte-identical content) exactly:

    origin/classic_era:Interface/AddOns/Blizzard_GameMenu/Shared/GameMenuFrame.lua
      62  function GameMenuFrameMixin:InitButtons()
      63      self:Reset();
      64
      65      local function GenerateMenuCallback(callback, customSoundEffect)
      66          return function()
      67              PlaySound(customSoundEffect or SOUNDKIT.IG_MAINMENU_OPTION);
      68              HideUIPanel(self);
      69              callback();          <-- the refused call
      70          end;
      71      end
     158      self:AddButton(GameMenuFrameMixin:GetLogoutText(), GenerateMenuCallback(Logout, SOUNDKIT.IG_MAINMENU_LOGOUT), exitDisabled);
     159      self:AddButton(EXIT_GAME, GenerateMenuCallback(Quit, SOUNDKIT.IG_MAINMENU_QUIT), exitDisabled);

`Logout` and `Quit` are engine (C) functions — hence `'UNKNOWN()'` — and the
refusal is a *protected-function* refusal, which the engine documents:

- `origin/classic_era:Interface/AddOns/Blizzard_APIDocumentationGenerated/RestrictedActionsDocumentation.lua:11-26`
  — `C_RestrictedActions.CheckAllowProtectedFunctions(object, silent)`:
  *"Returns true if the calling context has permissions to call protected
  functions on the supplied object."*
- same file `:83-92` — the `ADDON_ACTION_FORBIDDEN` event, payload
  `{ isTainted, function }`. That is exactly the shape of the operator's
  message (`AddOn 'TacoTip'` = the tainted addon, `'UNKNOWN()'` = the
  protected function's name the reporter could not resolve).

**VERIFIED** — `C_RestrictedActions` and `ADDON_ACTION_FORBIDDEN` exist on all
five branches (`classic_era`, `classic_anniversary`, `classic_titan`,
`forever`, `live` — 2 and ≥4 hits each).

So the refused call is `Logout()` (or `Quit()`) invoked from the GameMenu
button's `OnClick` script.

**VERIFIED** — the closure is installed as a *button script*:

- `origin/classic_era:Interface/AddOns/Blizzard_SharedXML/Shared/Frame/MainMenuFrameTemplates.lua:24-33`
  `MainMenuFrameMixin:AddButton(text, callback, …)` → `newButton:SetScript("OnClick", callback);`
- `MainMenuFrameTemplates.lua:14` — the buttons come from
  `self.buttonPool = CreateFramePool("BUTTON", self, self.buttonTemplate, …)`,
  i.e. they are **children of the GameMenu frame**.

**VERIFIED** — the closure captures the GameMenu frame: `HideUIPanel(self)` at
line 68, `self` being `GameMenuFrameMixin:InitButtons`'s receiver.

---

## 2. The six questions, per branch

All citations are `git show origin/<branch>:<path>`.

### Q1 — Is `GameTooltip` a child of `UIParent`?

| branch | verdict | citation |
|---|---|---|
| classic_era | **YES** | `Interface/AddOns/Blizzard_GameTooltip/Classic/GameTooltip.xml:13` — `<GameTooltip name="GameTooltip" frameStrata="TOOLTIP" hidden="true" parent="UIParent" inherits="GameTooltipTemplate">` |
| classic_anniversary | **YES** | same file, `:13` |
| classic_titan | **YES** | same file, `:13` |
| forever | **YES** | `Interface/AddOns/Blizzard_GameTooltip/Mainline/GameTooltip.xml:249` — `<GameTooltip name="GameTooltip" inherits="GameTooltipTemplate" parent="UIParent">` |
| live | **YES** | same file, `:249` |

### Q2 — Is the GameMenu frame a child of `UIParent`?

| branch | verdict | citation |
|---|---|---|
| classic_era | **YES** | `Interface/AddOns/Blizzard_GameMenu/Shared/GameMenuFrame.xml:4` — `<Frame name="GameMenuFrame" mixin="GameMenuFrameMixin" inherits="MainMenuFrameTemplate, CallbackRegistrantTemplate" toplevel="true" frameStrata="DIALOG" enableMouse="true" hidden="true" parent="UIParent">` |
| classic_anniversary | **YES** | same file, `:4` |
| classic_titan | **YES** | same file, `:4` |
| forever | **YES** | same file, `:7` |
| live | **YES** | same file, `:4` |

> **Correction to the brief.** The brief said the GameTooltip's parentage was
> verified for the three classic branches and "still needs checking" for
> `forever` and `live`. It is now checked: **the GameTooltip's parent is
> `UIParent` on all five branches**, at `Classic/GameTooltip.xml:13` (classic
> family) and `Mainline/GameTooltip.xml:249` (forever, live).

### Q3 — Is `InitButtons` called from `OnShow`, and does the closure capture `self`?

| branch | OnShow → InitButtons | closure | captures `self`? | Logout/Quit |
|---|---|---|---|---|
| classic_era | `:18` → `:29` (also `:47` OnEvent) | `:65-71` | **YES** (`:68 HideUIPanel(self)`) | `:158` Logout, `:159` Quit |
| classic_anniversary | `:18` → `:29` (`:47`) | `:65-71` | **YES** | `:158`, `:159` |
| classic_titan | `:36` → `:47` (`:65`) | `:93-99` | **YES** | `:186`, `:187` |
| forever | `:61` → `:72` (`:101`) | `:164-170` | **YES** | `:263`, `:264` |
| live | `:57` → `:68` (`:88`) | `:116-122` | **YES** | `:215`, `:216` |

The classic_era and classic_anniversary `GameMenuFrame.lua` files are
content-identical (181 lines each; only line endings differ), so the error's
`66`/`69` line numbers fit both. classic_titan is 209 lines, forever and live
have different offsets — **the operator's stack therefore identifies a
classic-family client, and the reported branch (Classic Era) is the one whose
line numbers match.**

### Q4 — Does `hooksecurefunc` accept the (table, method, hook) form?

**YES on all five branches.** Blizzard itself uses that exact form on every
branch:

    origin/<branch>:Interface/AddOns/Blizzard_Dispatcher/Blizzard_Dispatcher.lua:260
      hooksecurefunc(functionOwner, functionName, function(...) self:OnSecureFunc(functionOwner, functionName, ...) end);

Our vendored library uses the same form:
`Libs/LibDetours-1.0/LibDetours-1.0.lua:34` (`function lib:SecureHook`) →
`:73` `hooksecurefunc(funcTable, funcName, function(...) … end)`.

**Caveat (VERIFIED):** `hooksecurefunc(table, method, hook)` hooks a *method*.
`OnShow`/`OnHide`/`OnTooltipSetUnit` are **scripts**, not methods — there is
no `GameTooltip["OnShow"]` field to hook. So `hooksecurefunc` **cannot**
replace `Detours:ScriptHook` for the script hooks; it can only replace it for
`GameTooltip.FadeOut`, which *is* a method.

### Q5 — Does `GameTooltip` have a `FadeOut` method?

**Settled: `FadeOut` is an ENGINE method and it exists on all five clients.
`workshop.md` is wrong; the repo's comments are right.**

Evidence:

1. **VERIFIED — no Lua definition on any branch.** Whole-tree sweep of
   `origin/classic_era` for `function …:FadeOut` yields exactly two
   definitions, neither of them a tooltip:
   `Blizzard_ActionBar/Shared/StatusTrackingManager.lua:261`
   (`StatusTrackingBarContainerMixin:FadeOut`) and
   `Blizzard_SharedMapDataProviders/ClickToZoomDataProvider.lua:15`.
   A filtered sweep of the classic tree finds no tooltip `FadeOut` at all.
   `origin/live` / `origin/forever`: the only `FadeOut` reference in
   `Blizzard_GameTooltip/**` is the *call* `self:FadeOut()` at
   `Mainline/GameTooltip.lua:1017` (live) / `:1026` (forever).
2. **VERIFIED — absent from the generated API docs on all five.** No
   `FadeOut` entry in `Blizzard_APIDocumentationGenerated/**` on any branch.
3. **VERIFIED — Blizzard calls it unguarded on all five branches**, so the
   method must exist there or the client would raise on every mouse-out
   from the player/target frame:

   | branch | call site | wiring |
   |---|---|---|
   | classic_era | `Blizzard_UnitFrame/Classic/UnitFrame.lua:447` `GameTooltip:FadeOut();` | `Blizzard_UnitFrame/Classic/PlayerFrame.xml:374`, `TargetFrame.xml:380`, `PartyMemberFrame.lua:413,496`, `PetFrame.lua:159`, `Shared/CompactUnitFrame.xml:98` |
   | classic_anniversary | `Blizzard_UnitFrame/Classic/UnitFrame.lua:447` | same |
   | classic_titan | `Blizzard_UnitFrame/Classic/UnitFrame.lua:447` | same |
   | forever | `Blizzard_UnitFrame/Mainline/UnitFrame.lua:393` | — |
   | live | `Blizzard_UnitFrame/Mainline/UnitFrame.lua:386` | — |

4. **What the cited line actually is** (the brief asked): on
   `origin/classic_era`, `Blizzard_UnitFrame/Classic/UnitFrame.lua:442-449`
   is:

       function UnitFrame_OnLeave (self)
           self.UpdateTooltip = nil;
           if ( GetCVar("showNewbieTips") == "1" ) then
               GameTooltip:Hide();
           else
               GameTooltip:FadeOut();      <-- line 447
           end
       end

   It is a **Blizzard call site to the engine method**, not a definition —
   exactly as `options.lua:483-506` and `main.lua:4792-4807` say.

**Consequence for our tree:** the runtime probe
`type(GameTooltip.FadeOut) == "function"` (`main.lua:4779`,
`options.lua:508`) evaluates **TRUE on all five clients**, so
`Detours:SecureHook(TT, GameTooltip, "FadeOut", …)` (`main.lua:4780`,
`options.lua:530`) **is** installed when `instant_fade` is on, on every client.
That hook is a `hooksecurefunc` post-hook (`LibDetours:73`) — it does not
replace the method and it does not taint. **It is not a taint source.**

### Q6 — every taint-capable operation in our tree

See §4.

---

## 3. The chain

**VERIFIED (client source + our tree):**

1. Our addon puts addon code into the **script chain of Blizzard frames**.
   On the classic family that includes the *shared* `GameTooltip` itself
   (§4, T1–T3, T4, T6).
2. `GameTooltip` is a **child of `UIParent`** on all five branches (Q1), and
   `GameMenuFrame` is **also a child of `UIParent`** on all five branches (Q2).
3. The GameMenu's Logout/Quit button is a **child of the GameMenu frame**
   (`MainMenuFrameTemplates.lua:14,33`) whose `OnClick` is the closure from
   `GameMenuFrame.lua:66`, and that closure calls the protected
   `Logout()`/`Quit()` at `GameMenuFrame.lua:69` (classic family numbering).
4. The engine refuses that call when the executing context is tainted
   (`C_RestrictedActions.CheckAllowProtectedFunctions`, `RestrictedActionsDocumentation.lua:11-26`),
   and reports it as `ADDON_ACTION_FORBIDDEN {isTainted, function}`
   (`:83-92`) — the operator's message verbatim in shape.

**The structural link that makes the shared tooltip the carrier (VERIFIED):**
the shared `GameTooltip` is *the same object* the GameMenu's own buttons
anchor to. `MainMenuFrameTemplates.lua:38-44`:

    newButton:SetScript("OnEnter", function()
        local tooltip = GetAppropriateTooltip();
        tooltip:SetOwner(newButton, "ANCHOR_RIGHT");
        …

and `GetAppropriateTooltip()` returns the shared tooltip on every branch:

- `origin/classic_era:Interface/AddOns/Blizzard_SharedXMLBase/FrameUtil.lua:277-279`
  `return UIParent and GameTooltip or GlueTooltip;`
- `origin/live:…/FrameUtil.lua:289-291` — identical.

So the frame our addon taints is the frame Blizzard's GameMenu buttons bind
themselves to. Our hooks and the quit path share one object.

**The two taint rules this chain needs, stated by Blizzard itself (VERIFIED as
Blizzard's own prose):**

- *"incoming chat messages, which can be handled from tainted addon filters,
  would otherwise taint the frame"* —
  `origin/live:Interface/AddOns/Blizzard_ChatFrameBase/Shared/ChatFrameUtil.lua:58-59`
  → addon code handled inside a frame's script **taints that frame**.
- *"For insecure callers, this ApplyFilter closure captures current execution
  taint at the point of creation. … When ApplyFilter is called, that stored
  taint then re-activates and applies to execution."* —
  `origin/classic_era:Interface/AddOns/Blizzard_ChatFrameBase/Shared/ChatFrameFilters.lua:27-34`
  → a closure **captures** taint at creation and **re-activates** it when it
  is later called. This is exactly the GameMenu closure's shape.
- *"we need to ensure that the first registration of a filter doesn't taint all
  other filters -or- spread taint back to the chat frame"* —
  `origin/classic_era:Interface/AddOns/Blizzard_ChatFrameBase/Shared/ChatFrameFiltersSecure.lua:5-6`
  → taint **spreads back into** a Blizzard frame from a stored callback.

**ASSUMED (engine-side; not provable from the FrameXML mirror):** that the
taint on the shared `GameTooltip` reaches the GameMenu's Logout *button*, and
that the engine's check consults the tainted button rather than some global
flag. The mirror contains **no engine code** — taint propagation across the
frame hierarchy is not written down in any `.lua` in
`/home/sam/wow-ui-source` (verified by a whole-tree sweep for "taint":
the only prose about taint rules in the entire tree is the three quotes above
plus `Blizzard_SharedXMLBase/SecureTypes.lua:21`, `FrameUtil.lua:323,412,471`
and `Blizzard_FrameXML/SecureTemplates.lua:739`).

**UNKNOWN:** whether the block is classic-only. The classic family has three
extra taint-capable hooks that live/forever do not have (§4, T1–T3), which
makes Classic Era the most likely place to see it first — but the shared hooks
(T4–T9) are installed on **all five** clients, so the same chain exists
everywhere. There has been no in-game test on four of the five clients
(`bench/audits/2026-10-20-session-retrospective.md`), so this is exactly the
case where an absence claim would be a defect report and must not be made.

---

## 4. Every taint-capable operation in our tree

`T` = taint-capable. `S` = safe by construction (secure hook / read-only).
"always-on" = installed at addon load; "conditional" = only on a narrow path.

| id | file:line | operation | frame it touches | when | clients |
|---|---|---|---|---|---|
| **T1** | `main.lua:2962-2966` (via `hookTooltipScripts`, `main.lua:2946` `frame:HookScript`) | `HookScript("OnTooltipSetUnit", …)` | **GameTooltip** | always-on | **classic family only** |
| **T2** | `main.lua:3211-3216` (via `:2946`) | `HookScript("OnTooltipSetItem", …)` | GameTooltip, ShoppingTooltip1, ShoppingTooltip2, ItemRefTooltip | always-on | **classic family only** (those frames declare the script) |
| **T3** | `main.lua:3396-3398` (via `:2946`) | `HookScript("OnTooltipSetSpell", …)` | GameTooltip | always-on | **classic family only** |
| **T4** | `main.lua:3332-3338` (via `:3327`) | `HookScript("OnTooltipCleared", …)` | GameTooltip + 9 more tooltips | always-on | all five |
| **T5** | `main.lua:3341-3343` | `HookScript("OnShow", …)` | same list | always-on | live/forever (the classic `GameTooltip` declares no `OnShow`) |
| **T6** | `main.lua:3346-3354` | `HookScript("OnHide", …)` | same list | always-on | all five |
| **T7** | `main.lua:3805` | `CharacterFrame:HookScript("OnShow", …)` | CharacterFrame (`parent="UIParent"`, all five) | always-on | all five |
| **T8** | `main.lua:4054` | `InspectFrame:HookScript("OnShow", …)` | InspectFrame (`parent="UIParent"`, all five) | always-on | all five |
| **T9** | `main.lua:4067` | `InspectFrame:HookScript("OnHide", …)` | InspectFrame | always-on | all five |
| **T10** | `main.lua:2748` | `CreateFrame("StatusBar","TacoTipPowerBar", GameTooltip)` — addon frame **parented to the Blizzard tooltip** | GameTooltip (as parent) | conditional: `show_power_bar` | all five |
| **T11** | `main.lua:5072/5075` (`Detours:ScriptHook` → `funcTable:HookScript`, `LibDetours:169`) | `HookScript("OnShow"/"OnHide", …)` on the shared tooltip | GameTooltip | conditional: **tooltip mover shown** | all five |
| **T12** | `main.lua:5105-5106` | `GameTooltip:ClearAllPoints(); GameTooltip:SetPoint(…)` | GameTooltip | conditional: mover **being dragged** | all five |
| **T13** | `main.lua:5138-5141` | `GameTooltip:SetOwner(…); ClearAllPoints(); SetPoint(…)` | GameTooltip | conditional: mover shown / `ShowExample` | all five |
| **T14** | `main.lua:5185`, `main.lua:5202-5203` | `GameTooltip:EnableMouse(false)`, `GameTooltip:Hide()`, `GameTooltip:ClearAllPoints()` | GameTooltip | conditional: mover saved / disabled | all five |
| **T15** | `main.lua:3596-3597`, `3605-3607`, `3610-3611`, `3614-3615` | `tooltip:ClearAllPoints(); SetPoint(…); EnableMouse(false)` inside the `GameTooltip_SetDefaultAnchor` post-hook | the tooltip being anchored | conditional: managed owner only (our mover / mouse anchor) | all five |
| **T16** | `options.lua:1507`, `1515`, `1530` | `GameTooltip:SetOwner(…)/Show()/Hide()` | GameTooltip | conditional: options UI hover | all five |
| **T17** | `main.lua:4854` | `GameTooltip:Hide()` in a timer | GameTooltip | conditional: `instant_fade` | all five |
| — | `main.lua:3637` | `hooksecurefunc("GameTooltip_SetDefaultAnchor", …)` | — | always-on | **S** — secure hook, does not taint |
| — | `main.lua:4780`, `options.lua:530` | `Detours:SecureHook(GameTooltip,"FadeOut",…)` → `hooksecurefunc` (LibDetours:73) | — | conditional: `instant_fade` | **S** — secure post-hook, method identity preserved |
| — | `main.lua:3678-3685` | `GameTooltipStatusBar:HookScript("OnHide", …)` | — | **never runs** | **S / dead** — there is **no global `GameTooltipStatusBar` on any branch**; the client only has the *mixin* `GameTooltipStatusBarMixin` (`Blizzard_SharedXML/Classic/GameTooltipTemplate.lua:25`) and the `$parentStatusBar` frame (`…/GameTooltipTemplate.xml:138`). The `if (GameTooltipStatusBar) then` guard is false everywhere. |
| — | `main.lua:3033/3043/5146-5148` | `GameTooltip:AddLine/AddDoubleLine` | GameTooltip | conditional | data write, not a layout mutation |

### The classic-only difference (VERIFIED) — and why it matters

`dataPipelineActive(tooltip)` (`main.lua:2887-2894`) is true only when the
tooltip has the modern data-pipeline API. It is **false on the classic
family**:

- `origin/classic_era:Interface/AddOns/Blizzard_SharedXML/Classic/GameTooltipTemplate.xml:22`
  — `<GameTooltip name="GameTooltipTemplate" … mixin="GameTooltipMixin" …>`
  (the classic `GameTooltipMixin` has no `IsTooltipType`).
- `origin/live` / `origin/forever`:
  `Interface/AddOns/Blizzard_GameTooltip/Mainline/GameTooltip.xml:4`
  — `mixin="GameTooltipDataMixin"`, and
  `Mainline/GameTooltip.lua:951` — `GameTooltipDataMixin = CreateFromMixins(TooltipDataHandlerMixin)`,
  which is where `IsTooltipType` lives
  (`Blizzard_SharedXMLGame/Tooltip/TooltipDataHandler.lua:418`).
- There is **no** `mixin="TooltipDataHandlerMixin"` / `mixin="GameTooltipDataMixin"`
  anywhere in the classic trees (verified by grep on all three).

So on live/forever the unit callback is registered through the client's own
**secure** dispatch —
`origin/classic_era:…/Tooltip/TooltipDataHandler.lua:181-201`:

    local function AddCall(callType, keyType, func)
        if issecure() then … InternalAddCall(tbl, keyType, func);
        else
            local tbl = insecureTables[callType];
            local function InsecureCallback(...) forceinsecure(); return func(...); end
            AttributeDelegate:SetAttribute(InsertCallbackAttributes[tbl], { keyType, InsecureCallback });
        end
    end

— an attribute delegate, i.e. **no addon code in the tooltip's script chain**.
On the classic family the addon falls back to raw `HookScript` (T1/T2/T3).
That is the concrete, source-visible reason Classic Era is the client where
this bug surfaces.

---

## 5. The minimal fix

### What it must do

Stop addon code from running inside the **shared `GameTooltip`'s** script
chain, because that tooltip is the one Blizzard's GameMenu buttons anchor
themselves to (`MainMenuFrameTemplates.lua:39` + `FrameUtil.lua:277-279`) —
one object, two owners.

### The fix

**Wrap every addon callback that runs inside a Blizzard frame's script chain
in `securecall`, and do not install addon callbacks into the Blizzard
`GameTooltip` at all where the client offers a secure dispatch.**

Concretely, `main.lua` only — four sites:

| site | change |
|---|---|
| `main.lua:2946` (`hookTooltipScripts`) | `frame:HookScript(scriptName, handler)` → `frame:HookScript(scriptName, function(...) return securecall(handler, ...) end)` |
| `main.lua:3332`, `:3341`, `:3346` (`registerTooltipVisualClearing`) | same wrap |
| `main.lua:5072/5075` (mover's `Detours:ScriptHook`) | same wrap — `hooksecurefunc` **cannot** replace it, because `OnShow`/`OnHide` are scripts, not methods (Q4) |
| `main.lua:3805`, `:4054`, `:4067` (CharacterFrame / InspectFrame) | same wrap |

**Why `securecall`:** it is Blizzard's own idiom for exactly this problem.
`origin/classic_era:Interface/AddOns/Blizzard_BuffFrame/BuffFrame.lua:991`

    securecall(self.UpdateDuration, self, self.timeLeft); -- Taint issue with SecondsToTimeAbbrev

— Blizzard wraps the call so the taint does not spread into the frame. The API
is present on all five branches (the client source uses `securecall(` 34×
on each classic branch, 30× on forever and live).

**Cost:** one `securecall` per tooltip/character-pane/inspect-pane event
(microseconds). Nothing the player sees changes: same tooltip content, same
mover, same options, same saved variables, no `.toc` change, no locale change,
no harness change. Diff size ≈ 10 lines, all in `main.lua`.

### The classic-family improvement on top of it (bigger, optional)

On live/forever the unit trigger is already secure (`TooltipDataProcessor`).
On the classic family there is **no** secure dispatch for the classic
tooltip, so `securecall` is the only zero-visible-change option there. If the
operator wants the classic path to be *structurally* like the modern one, the
alternative is to drive the classic tooltip from an addon-owned ticker
instead of hooking the Blizzard frame — **but that costs hover latency**
(the tooltip content would be up to one tick stale), which the
`hover-latency` desk exists to protect. **Not recommended as the minimal fix.**

### Residual risk — stated plainly

`securecall` is the documented remedy against a *run-time* taint (addon code
running inside a frame's script). If the engine instead taints a frame at
**install** time (when the hook is registered), `securecall` changes nothing,
and the only remaining fix is to remove the hooks from Blizzard frames
entirely — a much larger change. **One in-game A/B settles it in a single
session:** load the build with the tooltip hooks (T1–T6) disabled and try to
log out. If logout works, the carrier is confirmed and the `securecall` wrap
is the minimal fix. If it still fails, the carrier is T7–T9 or the mover path,
and the hooks have to go.

**Do not narrow `isSecureMenuBusy()`** (`main.lua:4943-4961`) further — it
already covers the mover's ticker, both hooks, `ShowExample`, the drag
`OnUpdate` and the right-click confirm, and it is the wrong lever: it stops
*concurrent* mutation, it cannot un-taint a frame.

---

## 6. Corrections to standing knowledge

1. **`workshop.md` → "what the client actually does":**
   *"**`GameTooltip.FadeOut` exists only on live and forever** — the classic
   family has no `FadeOut` on the tooltip, so an instant-fade option is inert
   there and must say so."*
   → **WRONG.** `FadeOut` has no Lua definition on any branch; it is an engine
   method; Blizzard calls it unguarded on all five
   (`Blizzard_UnitFrame/Classic/UnitFrame.lua:447` on the classic family,
   `Blizzard_UnitFrame/Mainline/UnitFrame.lua:393` forever / `:386` live).
   The instant-fade option is **not** inert on the classic family, and
   `options.lua:507-509`'s runtime probe is the correct model. **This bullet
   should be corrected.** (The repo's `options.lua:483-506` and
   `main.lua:4792-4807` comments are correct as written.)
2. **`AGENTS.md`/`workshop.md` carry no statement about the quit taint.** The
   repo's own `main.lua:4923-4929` and `main.lua:4772-4778` already record
   the class of bug ("Running any of that while GameMenu owns the screen
   taints the quit path (ADDON_ACTION_FORBIDDEN)") — but the mitigation there
   is the `isSecureMenuBusy()` concurrency guard, which cannot address an
   always-on hook. That gap is what this audit closes.

---

## 7. What I could not establish

1. **The taint propagation rule itself.** The FrameXML mirror has no engine
   code; nothing in the whole tree documents how taint crosses a frame
   hierarchy. The two rules the chain needs (addon code inside a frame taints
   the frame; a closure captures creation-time taint) *are* stated by Blizzard
   in prose (§3, three citations) — but the hop from the shared `GameTooltip`
   to the GameMenu's Logout *button* is **ASSUMED**, not verified.
2. **Whether the block is Classic-Era-only.** The classic family has three
   extra hooks (T1–T3); the shared hooks (T4–T9) run on all five clients. No
   in-game observation exists for live, forever, classic_anniversary or
   classic_titan — so "it works on the other four" is **UNKNOWN** and must
   not be assumed in either direction.
3. **Whether `GameTooltip.FadeOut` is present at runtime on the classic
   family.** The source proves Blizzard *calls* it there unguarded; the
   engine-side method table is not in the mirror. The runtime probe at
   `main.lua:4779` / `options.lua:508` makes the question moot for behaviour,
   but the workshop bullet still needs correcting (see §6).
4. **Whether the operator had the tooltip mover open.** T11–T16 are
   conditional on it. The always-on hooks T1–T9 do not depend on it.
5. **Whether `TacoTip Extras` was also loaded.** The error names `TacoTip`,
   so the main addon is the one the engine blamed. `TacoTip_Extras` is a
   separate package with its own `.toc`; it has its own Blizzard-frame hooks
   (`TacoTip_Extras/Tooltips.lua:1589-1693`, `Frames.lua:1335-1398`,
   `Options.lua:628-633`) that were **not** audited here — they are out of
   this brief's scope (the brief named `main.lua`/`options.lua`), but they
   are worth a separate pass if the A/B above shows the block survives the
   `main.lua` fix.
