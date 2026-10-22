# The exit-game taint: the carrier, and the fix

- **desk:** `quit-taint-fix` · **date:** 2026-10-21 · **run_id:** `quittaintfix20261021`
- **kind:** client-source analysis + product fix. Product files WERE edited.
- **supersedes:** nothing. It **completes** `bench/audits/2026-10-20-quit-taint.md`,
  which analysed the chain but never opened the vendored library, and
  **corrects** its §5 recommendation in one respect (the carrier is not the
  shared `GameTooltip` — see §3).
- **evidence labels:** VERIFIED / ASSUMED / UNKNOWN, per `CAIRN.md`.
- **method:** `git -C /home/sam/wow-ui-source show origin/<branch>:<path>`
  (read-only) and read/grep of this repo. No web.

---

## 1. The operator's report

> 4x `[ADDON_ACTION_FORBIDDEN] AddOn 'TacoTip' tried to call the protected
> function 'UNKNOWN()'.`
> `[!BugGrabber/BugGrabber.lua]:554` → `:538` → `[C]: ?` → `[C]: ?` →
> `[Blizzard_GameMenu/Shared/GameMenuFrame.lua]:69: in function <...GameMenuFrame.lua:66>`

Client: **Classic Era** (the operator's own words). The refusal happens when
the player tries to **exit the game**.

## 2. The carrier — VERIFIED

**The add-on replaced the client's global `PlaySound` with addon code, and the
game menu's Logout/Quit callback calls that global two lines before the
protected `Logout()`/`Quit()`.**

### 2.1 The game menu's callback — VERIFIED on all five branches

    origin/classic_era:Interface/AddOns/Blizzard_GameMenu/Shared/GameMenuFrame.lua
      65      local function GenerateMenuCallback(callback, customSoundEffect)
      66          return function()
      67              PlaySound(customSoundEffect or SOUNDKIT.IG_MAINMENU_OPTION);
      68              HideUIPanel(self);
      69              callback();          <-- the refused call
      70          end;

The same three-line closure exists on every branch, at these lines:

| branch | `PlaySound` | `HideUIPanel` | `callback()` |
|---|---|---|---|
| `classic_era` | 67 | 68 | **69** |
| `classic_anniversary` | 67 | 68 | **69** |
| `classic_titan` | 95 | 96 | **97** |
| `forever` | 166 | 167 | **168** |
| `live` | 118 | 119 | **120** |

The operator's stack names `:66` (the closure) and `:69` (the refused call) —
**classic_era / classic_anniversary numbering**, i.e. the operator's client.

### 2.2 The replacement — VERIFIED

`Libs/LibForeverInspector/LibForeverInspector.lua:5001` (before this fix):

    inspectPlaySound = Detours:DetourHook(lib, "PlaySound", inspectSoundSink)

`Libs/LibDetours-1.0/LibDetours-1.0.lua:134` — a global detour is:

    rawset(_G, funcName, func)

so the client's global `PlaySound` **became addon code**. `Detours:DetourHook`
is the only mechanism in the tree that replaces a Blizzard global; `hooksecurefunc`
does not replace anything.

### 2.3 The gate — VERIFIED: Classic Era only

`LibForeverInspector.lua:177`:

    local isClassic = (WOW_PROJECT_CLASSIC ~= nil and WOW_PROJECT_ID == WOW_PROJECT_CLASSIC)

and `:4985` `if (not isClassic) then return false end`. The suppressor installs
at **file scope** (`:5011`). `WOW_PROJECT_CLASSIC` is the Classic Era project
only — TBC Anniversary is `WOW_PROJECT_BURNING_CRUSADE_CLASSIC`, Titanforge is
`WOW_PROJECT_WRATH_CLASSIC`, Forever and Retail are `WOW_PROJECT_MAINLINE`.
**The carrier existed on exactly the client's the operator reported it on.**

### 2.4 Why the engine refuses

The game's Logout/Quit callback is Blizzard code that calls `PlaySound` — now
addon code — and then calls the **engine** function `Logout()`/`Quit()`. The
protected call is refused when the executing context is tainted, and the
engine reports it as `ADDON_ACTION_FORBIDDEN { isTainted, function }`
(`Blizzard_APIDocumentationGenerated/RestrictedActionsDocumentation.lua:11-26`
and `:83-92`, present on all five branches). `Logout` and `Quit` are engine
functions — documented as `Type = "Function"` in the `ConnectionScript`
namespace (`Blizzard_APIDocumentationGenerated/ConnectionDocumentation.lua:86-93`,
all five branches) — and the reporter's `'UNKNOWN()'` is **its own failed
name-resolution of that payload**, not evidence that the function is
anonymous.

**The addon named in the report is `TacoTip` because the library ships inside
the TacoTip package.** (`TacoTip_Extras` was not loaded in that path; the
error names the addon that owns the tainted code.)

## 3. Why the 0.8.4 "quit-menu taint fix" could not have fixed it

The 0.8.4 entry in `CHANGELOG.md` ("Quit-menu taint fix (publish blocker)")
removed the `GameTooltip.FadeOut` **detour** and replaced it with a
`hooksecurefunc` post-hook, and added the anchor-hook unit gate. Both address
carriers **inside the shared `GameTooltip`**; neither touches the global
`PlaySound`. **The carrier was never in the tree the audit looked at**:
`bench/audits/2026-10-20-quit-taint.md` §7.5 states that the vendored
`Libs/` and `TacoTip_Extras` were out of its brief.

**Correction to that audit (VERIFIED):** its §5 recommendation — wrap every
addon callback that runs inside a Blizzard frame's script chain in
`securecall` — is right, and it has been applied here (§5). But its carrier
hypothesis (the shared `GameTooltip`) required an unproven hop: taint moving
from the tooltip to a **sibling** frame under a shared `UIParent`. The real
carrier needs **no such hop**: the tainted function is called **from the very
closure that makes the protected call**, two lines above it.

## 4. The fix (the carrier)

**The sound of a swallowed refusal is muted where the client ASKS for it, not
at `PlaySound`.**

The client plays a refusal's sound kit from `UIErrorsMixin:TryDisplayMessage`
(`origin/classic_era:Interface/AddOns/Blizzard_UIErrorsFrame/Classic/UIErrorsFrame.lua:140-149`):

    function UIErrorsMixin:TryDisplayMessage(messageType, message, r, g, b)
        if self:ShouldDisplayMessageType(messageType, message) then
            self:AddMessage(message, r, g, b, 1.0, messageType);

            local errorStringId, soundKitID, voiceID = GetGameMessageInfo(messageType);
            if voiceID then
                C_Sound.PlayVocalErrorSound(voiceID);
            elseif soundKitID then
                PlaySound(soundKitID);
            end
        end
    end

`GetGameMessageInfo` is called by **exactly two** places in the client
(`UIErrorsFrame.lua:142` and `Blizzard_Channels/VoiceUtils.lua:82`, both
branch-qualified above) and by **nothing** in the game menu. So:

| | before | after |
|---|---|---|
| client's global `PlaySound` | **replaced by addon code** | **the client's own function** |
| refusal's sound kit | swallowed at `PlaySound` | muted at `GetGameMessageInfo` (the sound kit id is returned as nil) |
| game's own menu sounds | addon code | the client's own function |
| `Logout()` / `Quit()` | refused | the client's own closure |

The `C_Sound.PlayVocalErrorSound` and `PlayVocalErrorSoundID` detours are
unchanged: neither is called by the game menu's closure (`PlayVocalErrorSoundID`
is only the deprecated alias `Blizzard_DeprecatedSoundScript/Deprecated_SoundScript.lua:9`
— VERIFIED).

## 5. The fix (the class) — `securecall`

The 2026-10-20 audit's recommendation is applied: **every addon callback that
runs inside a Blizzard frame's script chain now runs inside `securecall`**,
so the client does not taint that frame.

`securecall` is the engine's own containment primitive and Blizzard uses it
for exactly this shape — `Blizzard_BuffFrame/BuffFrame.lua:991`:

    securecall(self.UpdateDuration, self, self.timeLeft); -- Taint issue with SecondsToTimeAbbrev

and for the tooltip functions themselves —
`Blizzard_CommunitiesSecure/CommunitiesAddDialogOutbound.lua:9`
(`securecall("GameTooltip_SetBasicTooltip", GameTooltip, text, x, y, wrap);`)
and `Blizzard_CatalogShop/Blizzard_CatalogShop_Outbound.lua:17`
(`securecall("GameTooltip_Hide");`).

It is an engine global on every supported client — Blizzard captures it as a
local the same way it captures `forceinsecure`
(`Blizzard_FrameXML/SharedPetBattleTemplates.lua:5`
`local securecall = securecall;`). **VERIFIED on all five branches.**

Wrapped (every site where addon code enters a Blizzard frame's script chain):

| file | site |
|---|---|
| `main.lua` | `hookTooltipScripts` — the `OnTooltipSetUnit` / `OnTooltipSetItem` / `OnTooltipSetSpell` handlers |
| `main.lua` | `registerTooltipVisualClearing` — `OnTooltipCleared` / `OnShow` / `OnHide` on the shared GameTooltip and nine other tooltips |
| `main.lua` | the `GameTooltip_SetDefaultAnchor` post-hook **body** (a `hooksecurefunc` does not replace the hooked function, but its body still runs as addon code in the caller's chain) |
| `main.lua` | `CharacterFrame:OnShow`, `InspectFrame:OnShow` / `OnHide` |
| `main.lua` | the mover's `Detours:ScriptHook(GameTooltip, "OnShow"/"OnHide")` |
| `main.lua` | the `GameTooltip.FadeOut` secure post-hook body |
| `options.lua` | the `GameTooltip.FadeOut` secure post-hook body; the options panel's hover tooltip writes to the shared GameTooltip |
| `TacoTip_Extras/Frames.lua` | `boundedCallback` — the single boundary every Extras callback on a Blizzard frame passes through |
| `TacoTip_Extras/Tooltips.lua` | the shared GameTooltip's script hooks (`OnTooltipSetUnit` / `OnTooltipSetItem` / `OnTooltipCleared` / `OnHide`, and the `OnUpdate` poll / `OnShow` fallbacks) |

**Nothing is left out of the class.** Every addon callback that enters a
Blizzard frame's script chain now runs inside `securecall`.

## 6. The sound rule (operator instruction)

> "the sound refusal should only be out of range, bcuz on classic era it was
> having problems, it kept spamming out of range" — "its only for the inspect
> range part. that was the issue we were having."

Implemented in `noteSuppressedRefusal` (`LibForeverInspector.lua`): **only a
refusal whose resolved name is `ERR_OUT_OF_RANGE` arms a sound latch.** A
refusal that is not about the inspect range keeps its sound — the text is
still swallowed (the 0.8.3 popup fix, unchanged), but the player is told that
something happened.

**Recorded asymmetry:** for a non-range refusal the player now hears the
error sound with no text. The alternative — restricting the *message*
suppression to the range case as well — would put the red text back for
`ERR_UNIT_NOT_FOUND` / `ERR_INVALID_INSPECT_TARGET`, which the proximity scan
can trigger repeatedly. The operator's instruction named the **sound**, and
the message suppression is the 0.8.3 popup fix; the asymmetry is stated here
rather than decided silently.

## 7. Pins and the revert-to-fail proof

| pin | what it holds | revert map |
|---|---|---|
| `detect_test.lua` — "the client's global PlaySound is not replaced" | the carrier's precondition | restore the `PlaySound` detour → **RED** (`replaced=true`) |
| `detect_test.lua` — "a range refusal with a sound kit plays no sound" | the sound is still muted | stop muting the sound kit id → RED |
| `detect_test.lua` — "a refusal that is not about range keeps its sound" | the operator's rule | arm every refusal → RED |
| `detect_test.lua` — "the client's own sound still plays" | no unrelated sound is swallowed | arm the latch for every sound → RED |
| `taint_test.lua` — three "runs inside securecall" pins | the containment is installed | unwrap `runUntainted` → **3 RED** |

**Revert-to-fail proven on a copy** (`/tmp/opencode/revert-test`):

    # REVERT 1 -- the PlaySound detour restored:
    probe guard taint: the client's global PlaySound is not replaced FAIL  replaced=true

    # REVERT 2 -- runUntainted unwrapped (calls the function directly):
    CLASSIC_ERA  FAIL containment: the GameTooltip's OnShow hook runs inside securecall (secureCalls=0)
    CLASSIC_ERA  FAIL containment: the GameTooltip's OnHide hook runs inside securecall (secureCalls=0)
    CLASSIC_ERA  FAIL containment: the anchor post-hook body runs inside securecall (secureCalls=0)

**The harness mock was corrected, because it was not reproducing the client.**
`Tests/harness/detect_test.lua` played the refusal's sound from inside its
`UIErrorsFrame.AddMessage` mock and called `PlaySound` directly. The client
plays the sound from `TryDisplayMessage`, **after** `AddMessage`, whether or
not the message was added (`UIErrorsFrame.lua:140-149`). The mock now
reproduces that path — a mock that plays the sound from inside `AddMessage`
never plays it for a swallowed message, which is the "a pin that cannot fail"
shape from `hands-up.md`.

## 8. What I could not establish

1. **The taint-propagation rule itself.** The FrameXML mirror has no engine
   code. That a replaced global taints the closure that calls it is the
   standard rule and the reason `hooksecurefunc` exists, but it is not written
   down in any `.lua` in the mirror. **ASSUMED**, with Blizzard's own use of
   `securecall` as the supporting argument.
2. **Whether the other four clients were affected.** The carrier was
   Classic-Era-only by construction (§2.3), so the other four could not have
   had it. The `securecall` class (§5) was present on all five; whether it
   produced a visible refusal anywhere else is **UNKNOWN**.
3. **Whether the operator has `TacoTip Extras` loaded.** The error names
   `TacoTip`; the Extras callbacks are now contained (§5) but were not
   audited for the carrier.
4. **The engine's `isClassic` derivation** is the library's own; the
   project constants were confirmed from the repo's detection table and the
   harness's five-client list, not from the client's own constants file.

## 9. Corrections to standing knowledge
1. **`bench/audits/2026-10-20-quit-taint.md` §5 "the minimal fix" is
   incomplete.** Wrapping the script-chain callbacks in `securecall` does not
   touch a replaced Blizzard **global**. The carrier was a global replacement
   in the vendored library, which that audit's brief excluded (§7.5).
2. **A `hooksecurefunc` post-hook is not a taint boundary.** It does not
   replace the hooked function, but its **body** still runs as addon code
   inside the caller's script chain. The 0.8.4 "secure post-hook instead of
   a detour" fix for `GameTooltip.FadeOut` therefore did not contain the taint
   it was meant to contain.
3. **`workshop.md` → "what the client actually does" needs a bullet:** the
   game menu's Logout/Quit callback calls the client's global `PlaySound`
   immediately before the protected `Logout()`/`Quit()` — on every client, at
   `GameMenuFrame.lua:67/69` (classic_era), `:67/69` (classic_anniversary),
   `:95/97` (classic_titan), `:166/168` (forever), `:118/120` (live).
   **A global that the game menu calls must never be replaced by an add-on.**

---

## 10. The second pass (same day, after the fix landed)

The operator asked for one more pass before the build ships: every claim
re-checked **per client**, nothing assumed, nothing already earned broken.
`classic_era` and `classic_anniversary` are **not** one client family, and
neither are `retail` and `forever` — so every row below is a branch.

### 10.1 The per-branch table (VERIFIED, each row read from the mirror)

| fact | classic_era | classic_anniversary | classic_titan | forever | live |
|---|---|---|---|---|---|
| game-menu closure: `PlaySound` / `HideUIPanel` / `callback()` | `GameMenuFrame.lua:67/68/69` | `:67/68/69` | `:95/96/97` | `:166/167/168` | `:118/119/120` |
| `GetGameMessageInfo` call sites in `Interface/` | 2 (`UIErrorsFrame.lua:142`, `VoiceUtils.lua:82`) | 2 (same two paths) | 2 (same two paths) | **3** (`UIErrorsFrame/Mainline/:150` + **two** `VoiceUtils` files, `Classic/:82` and `Mainline/:88`) | 2 (`UIErrorsFrame/Mainline/:150`, `VoiceUtils.lua:82`) |
| any `GetGameMessageInfo` call on the game-menu path | **no** | **no** | **no** | **no** | **no** |
| `securecall(` call sites in `Interface/` | 171 | 171 | 171 | 121 | 120 |
| `local securecall = securecall;` captures | 7 | 7 | 7 | 7 | 7 |
| `xpcall(f, handler, ...)` — the 3-argument form Blizzard uses | 3 sites | 3 sites | 3 sites | 5 sites | 4 sites |
| shared `GameTooltip` declares `OnTooltipSetUnit` / `OnTooltipSetItem` / `OnTooltipSetSpell` | yes / yes / yes | yes / yes / yes | yes / yes / yes | **no / no / no** | **no / no / no** |
| shared `GameTooltip` declares `OnShow` | **no** | **no** | **no** | yes | yes |
| shared `GameTooltip` declares `OnHide` | yes | yes | yes | yes | yes |
| shared `GameTooltip` declares `OnTooltipCleared` | **no** | **no** | **no** | yes (`SharedTooltipTemplates.xml`) | yes (`SharedTooltipTemplates.xml`) |
| shared `GameTooltip` has `SetBackdrop` (template inherits `TooltipBackdropTemplate`) | yes | yes | yes | no (it has a `NineSlice` child) | no (it has a `NineSlice` child) |
| `Mixin(GameTooltip, BackdropTemplateMixin)` guard fires? | **no** | **no** | **no** | **no** | **no** |
| global `GameTooltipStatusBar` exists | **no** | **no** | **no** | **no** | **no** |
| `InspectGuildFrame_Update` defined | **no** | **no** | **no** | yes (2 files) | yes (1 file) |

**What the table settles:**

1. **The carrier is Classic-Era-only by construction**, and no other branch
   can reach it: the suppressor installs only when
   `WOW_PROJECT_ID == WOW_PROJECT_CLASSIC`, which is Classic Era alone. The
   sound interception now sits on `GetGameMessageInfo`, which **no** branch's
   game-menu path calls.
2. **`securecall` exists on all five** and Blizzard captures it as a local on
   all five — and the load-time probe (§10.3) removes even the doubt.
3. **WoW's `xpcall` forwards extra arguments on all five** (Blizzard uses the
   3-argument form on every branch), so `safeCall(fn, args...)` — and the
   `securecall` chain built on it — passes its arguments on every client.
4. **The `Mixin(GameTooltip, BackdropTemplateMixin)` guard never fires on any
   client**: the classic clients' template inherits `TooltipBackdropTemplate`
   (so `SetBackdrop` exists) and the modern pair's template carries a
   `NineSlice` child. The shared GameTooltip is therefore never modified by
   that path.
5. **`GameTooltipStatusBar` is not a global on any client** (only the mixin
   `GameTooltipStatusBarMixin` and the `$parentStatusBar` template child
   exist), so `main.lua`'s `if (GameTooltipStatusBar) then … HookScript … end`
   is dead everywhere. The harness models the global as existing; that mock
   inaccuracy is harmless, because the guard is false in game.
6. **`InspectGuildFrame_Update` exists only on forever and live**, so that
   global replacement is never installed on a classic client. It is a
   Blizzard global replaced with addon code, so it is recorded as a residual
   (§10.5) — not changed: the game menu never calls it, and the replacement
   ships today in 0.8.4.

### 10.2 A defect this pass caught — in the fix itself

`TacoTip_Extras/Tooltips.lua`'s new `contained()` wrapper closed over `...`
inside a **non-vararg** inner function. In the Lua 5.1 WoW ships, `...`
outside a vararg function is a **compile error**: the file failed to load and
the Extras harness went 36/42 red. The wrapper now uses the same vararg-body
shape as `Frames.lua`'s `boundedCallback` (`local function bounded(...)`),
which forwards the arguments unchanged.

**It is recorded here because it is the shape of mistake worth remembering:**
a containment wrapper that swallows a raise also swallows the evidence of the
raise, and a wrapper that tries to catch the raise *after* the swallow has to
catch it **inside** the containment or the error counter never moves.

### 10.3 The load-time `securecall` probe (new)

`securecall` is read once at load and **probed**: a trivial function is run
through it, and only a probe that actually RAN arms the containment.

    local probeRan = false
    local probeOk = pcall(securecall, function() probeRan = true end)
    if (probeOk and probeRan) then secureCallFn = securecall end

**Why this matters at 120k downloads:** if any build ever refused addon code
to call `securecall`, every tooltip event would raise — on every client, in
the hot path. One probe at load turns that into the documented fallback (the
callback runs directly, and the taint guard is simply absent) instead of a
broken tooltip. The probe costs one call, once.

### 10.4 Error containment closed at the two gaps

`securecall` swallows a raise and returns nil, so a payload that is not
wrapped in its own `pcall` would fail **silently** — the exact shape the
workshop's audits keep hitting. Two gaps were found and closed:

| site | before | now |
|---|---|---|
| `options.lua`'s options-panel hover tooltip | `runUntainted(function() … end)` — a raise would vanish | `runUntainted(safeCall, function() … end)` — the raise is reported through `geterrorhandler()` |
| `TacoTip_Extras/Tooltips.lua`'s `contained()` | `Core.RunUntainted(fn, …)` — a raise would vanish | the raise is caught by a `pcall` **inside** the containment and reported through the surface's own `noteRenderError` (counts, keeps the last message, reports once per distinct message) |

Every other containment site already had its own containment: the tooltip
handlers through `safeCall`, the anchor post-hook through an explicit
`pcall` with a counter, the character and inspect panes through their own
`pcall` and counters, the mover through `safeCall`, the Extras' frame
callbacks through `boundedCallback`.

### 10.5 Residual items — recorded, NOT changed

Each of these is pre-existing (it ships in 0.8.4 today), is **not** on the
game menu's path, and is not reachable by the fix. They are listed so the
next desk inherits the facts rather than re-deriving them.

1. **`TacoTip_Extras/Options.lua`'s help hover** writes to the shared
   GameTooltip from an **add-on-owned** frame's script chain — so the taint
   lands on an add-on frame, not on a Blizzard chain. Same for
   `options.lua`'s hover, which is contained anyway.
2. **Add-on children under the shared GameTooltip**: the backdrop frame
   (`main.lua`), the portrait texture, the 3D portrait (`PlayerModel`), and
   the power bar (`StatusBar`). A child of a Blizzard frame is not a script
   chain, and the game menu never touches the shared tooltip.
3. **`main.lua`'s per-tooltip `Mixin(tooltip, BackdropTemplateMixin)`** can
   fire for a tooltip that has neither `NineSlice` nor `SetBackdrop`. It
   does not fire for the shared GameTooltip on any client (§10.1).
4. **`InspectGuildFrame_Update`** (forever/live only) is a Blizzard global
   replaced with addon code.
5. **`rawset(StaticPopupDialogs, "_TacoTipDragButtonConfirm_", …)`** adds one
   key to a Blizzard table, on the mover's right-click confirm.

### 10.6 What this pass did NOT establish

- The taint-propagation rule itself is still engine-side (§8.1).
- Whether the operator's session had `TacoTip Extras` loaded is still
  unknown; the Extras' Blizzard-frame callbacks are contained now, so the
  next carrier, if there is one, would have to be elsewhere.
- The **other four clients** have never been observed in game by the
  operator. Every claim about them is a claim about the mirror, not about
  what the player sees.

---

## 11. The independent cross-client sweep (a second lane) — and what it changed

A second read-only lane ran the cross-client sweep against the mirror with
the per-branch instruction (five clients, not two families). Its artifact:
`bench/audits/2026-10-21-crossclient-taint-surfaces.md`. **It found a real
gap in the fix, and it corrected me.**

### 11.1 What it found that I had wrong

**The tooltip's status bar IS a live global on every client.**

I had checked the tree for the identifier `GameTooltipStatusBar` and found
**zero hits on all five branches**, and concluded (with the 2026-10-20 audit)
that `main.lua`'s `if (GameTooltipStatusBar) then GameTooltipStatusBar:HookScript("OnHide", …)`
was dead code everywhere.

**That was wrong, and the lane was right.** The classic chain declares the
status bar as

    origin/classic_era:Interface/AddOns/Blizzard_SharedXML/Classic/GameTooltipTemplate.xml:138
      <StatusBar name="$parentStatusBar" mixin="GameTooltipStatusBarMixin" hidden="true">

and the modern chain as

    origin/forever, origin/live:Interface/AddOns/Blizzard_GameTooltip/Mainline/GameTooltip.xml:9
      <StatusBar parentKey="StatusBar" name="$parentStatusBar" mixin="GameTooltipUnitHealthBarMixin" …>

**The `$parent` prefix makes the child's global the parent's name plus the
child's** — the same rule this add-on already depends on for
`$parentTextLeft1` -> `GameTooltipTextLeft1` (it reads `_G["GameTooltipTextLeft" .. idx]`
at render time). So the global `GameTooltipStatusBar` **exists on all five
clients**, and that hook is an **always-on** insertion of addon code into a
Blizzard frame's script chain.

**A grep for an identifier is not a proof of absence when the XML spells the
name differently.** The lane's correction is the reason this section exists,
and the audit's "never runs" claim is **withdrawn**.

**Fixed:** the hook is now contained (`main.lua`, `status-bar` stage), and
`taint_test.lua` pins that its handler runs inside `securecall`. Revert map:
unwrap `runUntainted` -> the pin goes red (proved).

### 11.2 What it confirmed

- **The replaced-global inventory** (per branch): `GetGameMessageInfo` and
  `PlayVocalErrorSoundID` (classic_era only — the suppressor installs only
  when `WOW_PROJECT_ID == WOW_PROJECT_CLASSIC`), `InspectGuildFrame_Update`
  (forever and live only), and `SlashCmdList` (**fallback only** — both
  `options.lua:700` and `gearscore.lua:226` only `rawset` it when
  `rawget(_G, "SlashCmdList")` is nil, so the client's own proxy is never
  replaced). Two blizzard **table fields** are replaced on classic_era only:
  `UIErrorsFrame.AddMessage` and `C_Sound.PlayVocalErrorSound`. `Mixin` only
  ADDS fields, and `hooksecurefunc` replaces nothing.
- **No collisions with the game-menu path on any branch**: none of the
  replaced globals appears anywhere under
  `Interface/AddOns/Blizzard_GameMenu/` on the five branches. The only
  overlaps with the game menu's frames are additive (`GameTooltip` via
  `Mixin`, `GameTooltip_SetDefaultAnchor` and `GameTooltip.FadeOut` via
  post-hooks, one added `StaticPopupDialogs` key).
- **`PlaySound` is not replaced on any branch** — the carrier is gone.
- **The backdrop surface** (§10.1): the shared GameTooltip reaches a
  **NineSlice child on all five clients**, and `SetBackdrop` is **absent on
  all five** (it belongs to `BackdropTemplateMixin`, which no tooltip chain
  mixes in). The classic chain additionally exposes `SetBackdropColor` /
  `SetBackdropBorderColor` (routed to the NineSlice); forever and live expose
  neither. **So the legacy no-NineSlice graft in `main.lua` is dead on every
  client** — which is what this add-on's own in-game suite already records
  (`Tests/TacoTip_Forever_Tests.lua` -> `BackdropTemplateContract`), and what
  `main.lua`'s own comments and its `/tacotip diag` line say. My earlier
  inference ("the classic template inherits `TooltipBackdropTemplate`, so it
  has `SetBackdrop`") was **wrong**: `TooltipBackdropTemplate` is
  NineSlice-based, and `SetBackdrop` is not part of it. The conclusion is the
  same either way — the Mixin does not fire on the shared tooltip on any
  client — but the reason is now the correct one.
- **`InspectGuildFrame_Update`** exists only on forever and live, and is Lua
  there (`Blizzard_InspectUI/Mainline/InspectGuildFrame.lua:17`); it is never
  on the game-menu path.

### 11.3 What the lane could not establish (recorded)

1. Whether `GameTooltipStatusBar` is a live Lua global **at runtime** — the
   XML loader is engine C++. The `$parent` -> global step is VERIFIED for
   the sibling `$parentTextLeft1` -> `GameTooltipTextLeft1` on all five
   branches (Blizzard's own Lua uses it bare, and so does this add-on), and
   the `<Frames>`-child step is the inferred one. An in-game
   `/dump _G.GameTooltipStatusBar` would settle it. **The fix is safe either
   way: the hook is now contained.**
2. Whether classic_era and classic_anniversary **behave** alike — their
   files are byte-identical (line endings only) and the mirror has no engine
   code. Same caveat for the other three.
3. The taint-propagation rule itself — engine-side, still **ASSUMED**.
4. Which branches the operator has actually run — only Classic Era is
   reported; the other four are **UNKNOWN** behaviourally.
