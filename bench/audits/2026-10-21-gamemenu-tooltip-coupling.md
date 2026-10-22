# The game menu ↔ shared `GameTooltip` coupling — client source, five branches

- **desk:** `taint-client-source-2026-10-21` · **date:** 2026-10-21 ·
  **run_id:** `taintclientsrc`
- **kind:** client-source analysis (read-only). **No product file was edited.**
  **No product change is proposed here** — this is a client-truth artifact.
- **leads, not authority:** `bench/audits/2026-10-20-quit-taint.md` (desk
  `quit-taint`) and `bench/audits/2026-10-20-session-retrospective.md`. Every
  claim below was re-derived from the mirror; the prior audit is quoted only
  where this desk agrees with it, and contradicted where it does not (§10).
- **evidence labels:** VERIFIED / ASSUMED / UNKNOWN, per `CAIRN.md`.
- **method:** `git -C /home/sam/wow-ui-source show origin/<branch>:<path>`,
  `git -C /home/sam/wow-ui-source grep -n … origin/<branch> -- <path>`,
  `git -C /home/sam/wow-ui-source ls-tree -r --name-only origin/<branch>`,
  `git -C /home/sam/wow-ui-source diff --stat` (all read-only). No web. No
  state-changing git. The mirror was not modified
  (`git -C /home/sam/wow-ui-source status --porcelain` unchanged, §12).
- **branches swept:** `origin/classic_era`, `origin/classic_anniversary`,
  `origin/classic_titan`, `origin/forever`, `origin/live`.

---

## 1. What this artifact establishes, and what it does not

**VERIFIED — the structural coupling.** On all five branches the game menu's
button tooltip path and the shared `GameTooltip` are the *same object*:

    GetAppropriateTooltip()  ->  the global `GameTooltip`  ->  the frame
                                 the addon hooks

So the frame an addon taints by hooking `GameTooltip`'s script chain is
literally the frame the game menu binds its disabled-button tooltip to. That
coupling is real and is identical on all five branches.

**ASSUMED — the taint hop.** Per `CAIRN.md`, the engine's taint-propagation
rules are **not** in the FrameXML mirror. Nothing in this artifact claims how
taint moves from the shared `GameTooltip` to the GameMenu's Logout button, or
that it does. What would verify it: an in-game A/B on the operator's client
(load the build with the tooltip hooks disabled, then try to log out), plus the
engine-side taint rules, which live in the client binary, not the mirror.

**This artifact does not propose a fix.** The prior audit's `securecall`
proposal is not re-litigated here.

---

## 2. Q1 — the menu-button tooltip path

### 2.1 The handlers

The game-menu buttons are created by `MainMenuFrameMixin:AddButton`. The
`OnEnter`/`OnLeave` tooltip handlers are installed **only when the button is
disabled and has a disabled-text** — `if isDisabled and disabledText`
(`MainMenuFrameTemplates.lua:37`). A normal (enabled) Logout/Exit button
installs **no tooltip handlers at all** (`:50-51` sets them to `nil`).

**`origin/classic_era` · `origin/classic_anniversary` ·
`origin/classic_titan`** — identical file, identical line numbers —
`Interface/AddOns/Blizzard_SharedXML/Shared/Frame/MainMenuFrameTemplates.lua`:

    24	function MainMenuFrameMixin:AddButton(text, callback, isDisabled, disabledText)
    25		local newButton = self.buttonPool:Acquire();
    ...
    32		newButton:SetText(text);
    33		newButton:SetScript("OnClick", callback);
    34	
    35		newButton:SetMotionScriptsWhileDisabled(true);
    36		newButton:SetEnabled(not isDisabled);
    37		if isDisabled and disabledText then
    38			newButton:SetScript("OnEnter", function()
    39				local tooltip = GetAppropriateTooltip();
    40				tooltip:SetOwner(newButton, "ANCHOR_RIGHT");
    41				tooltip:SetText(text);
    42				GameTooltip_AddErrorLine(tooltip, disabledText);
    43				tooltip:Show();
    44			end);
    45	
    46			newButton:SetScript("OnLeave", function()
    47				GetAppropriateTooltip():Hide();
    48			end);
    49		else
    50			newButton:SetScript("OnEnter", nil);
    51			newButton:SetScript("OnLeave", nil);
    52		end

**`origin/forever` · `origin/live`** — same code, shifted by 8 lines —
`Interface/AddOns/Blizzard_SharedXML/Shared/Frame/MainMenuFrameTemplates.lua`:

    45		if isDisabled and disabledText then
    46			newButton:SetScript("OnEnter", function()
    47				local tooltip = GetAppropriateTooltip();
    48				tooltip:SetOwner(newButton, "ANCHOR_RIGHT");
    49				tooltip:SetText(text);
    50				GameTooltip_AddErrorLine(tooltip, disabledText);
    51				tooltip:Show();
    52			end);
    53	
    54			newButton:SetScript("OnLeave", function()
    55				GetAppropriateTooltip():Hide();
    56			end);
    57		else
    58			newButton:SetScript("OnEnter", nil);
    59			newButton:SetScript("OnLeave", nil);
    60		end

(forever/live have an extra narration block at `:36-41` and
`self.buttonCount` bookkeeping at `:22`/`:36`; the tooltip path is untouched
by those.)

### 2.2 The complete tooltip call list, in order

| # | call | classic family (`classic_era`, `classic_anniversary`, `classic_titan`) | `forever`, `live` |
|---|---|---|---|
| 1 | `GetAppropriateTooltip()` | `MainMenuFrameTemplates.lua:39` | `:47` |
| 2 | `tooltip:SetOwner(newButton, "ANCHOR_RIGHT")` | `:40` | `:48` |
| 3 | `tooltip:SetText(text)` | `:41` | `:49` |
| 4 | `GameTooltip_AddErrorLine(tooltip, disabledText)` | `:42` | `:50` |
| 5 | `tooltip:Show()` | `:43` | `:51` |
| 6 | `GetAppropriateTooltip():Hide()` (OnLeave) | `:47` | `:55` |

**VERIFIED — the calls the menu does NOT make.** The menu path contains
**no** `ClearLines`, **no** `ClearAllPoints`, **no** `SetPoint`, **no**
`EnableMouse`, **no** `FadeOut`, **no** `SetPadding`. The only indirect call
is #4, `GameTooltip_AddErrorLine`, which reduces to `tooltip:AddLine(...)`:

- classic family — `Interface/AddOns/Blizzard_GameTooltip/Classic/GameTooltip.lua:139-149`

      139	function GameTooltip_AddErrorLine(tooltip, text, wrap)
      140		GameTooltip_AddColoredLine(tooltip, text, RED_FONT_COLOR, wrap);
      141	end
      142	
      143	function GameTooltip_AddColoredLine(tooltip, text, color, wrap)
      144		local r, g, b = color:GetRGB();
      145		if wrap == nil then
      146			wrap = true;
      147		end
      148		tooltip:AddLine(text, r, g, b, wrap);
      149	end

- `forever`, `live` — `Interface/AddOns/Blizzard_SharedXML/SharedTooltipTemplates.lua:158-172`

      158	function GameTooltip_AddErrorLine(tooltip, text, wrap, leftOffset)
      159		GameTooltip_AddColoredLine(tooltip, text, RED_FONT_COLOR, wrap, leftOffset);
      160	end
      ...
      166	function GameTooltip_AddColoredLine(tooltip, text, color, wrap, leftOffset)
      167		local r, g, b = color:GetRGB();
      168		if wrap == nil then
      169			wrap = true;
      170		end
      171		tooltip:AddLine(text, r, g, b, wrap, leftOffset);
      172	end

**VERIFIED — a duplicate definition on the classic family.** The classic tree
carries **two** `GameTooltip_AddErrorLine` definitions with the same name:

- `Blizzard_GameTooltip/Classic/GameTooltip.lua:139` (signature
  `(tooltip, text, wrap)`)
- `Blizzard_SharedXML/SharedTooltipTemplates.lua:158` (signature
  `(tooltip, text, wrap, leftOffset)`)

The later-loaded file wins at runtime. Both are Blizzard code and both reduce
to the same `tooltip:AddLine` call, so the observable behaviour is the same;
but the duplicate is a real fact of the classic tree and is worth knowing
before anyone greps for "the" definition.

### 2.3 Branch-specific variants

**VERIFIED** — there is no other game-menu tooltip path:

- classic family: `Blizzard_GameMenu/Classic/GameMenuFrameOverrides.lua` is
  5 lines and contains only `GameMenuFrameMixin:GetLogoutText()` (`:2-5`).
- `forever`, `live`: `Blizzard_GameMenu/WoWLabs/GameMenuFrame.lua` +
  `.xml` are the **WoW Labs** experimental menu. A whole-tree grep for
  `Tooltip` under `Interface/AddOns/Blizzard_GameMenu/WoWLabs/` returns
  **nothing** on `forever` and on `live` — that menu has no tooltip path.
- `Blizzard_GameMenu/Shared/GameMenuFrame.lua` contains **no** tooltip call
  on any of the five branches (grep for `Tooltip` under `Blizzard_GameMenu/`
  hits only `MainMenuFrameTemplates.lua`).

### 2.4 Where the buttons live

**VERIFIED** — the buttons are pooled children of the GameMenu frame, and
their `OnClick` is the callback closure:

    Interface/AddOns/Blizzard_SharedXML/Shared/Frame/MainMenuFrameTemplates.lua
      14		self.buttonPool = CreateFramePool("BUTTON", self, self.buttonTemplate, HideAndClearAnchorsAndLayoutIndex);
      33		newButton:SetScript("OnClick", callback);

`self.buttonTemplate` is `MainMenuFrameButtonTemplate`
(`Blizzard_SharedXML/Classic/Frame/MainMenuFrameTemplates.xml:11-20`;
`MainMenuFrameTemplate` itself is at `:18`, `mixin="MainMenuFrameMixin"`).

`GameMenuFrame` is a child of `UIParent` on all five branches
(`Blizzard_GameMenu/Shared/GameMenuFrame.xml:4`), and the shared `GameTooltip`
is a child of `UIParent` on all five branches
(classic `Blizzard_GameTooltip/Classic/GameTooltip.xml:13`;
mainline `Blizzard_GameTooltip/Mainline/GameTooltip.xml:249`).

---

## 3. Q2 — which tooltip `GetAppropriateTooltip` returns

### 3.1 Definitions

**VERIFIED — there are TWO global definitions on the classic family and ONE on
`forever`/`live`.** Whole-tree sweep for `function GetAppropriateTooltip`:

| branch | definition site | body |
|---|---|---|
| `classic_era` | `Blizzard_SharedXMLBase/FrameUtil.lua:277` | `return UIParent and GameTooltip or GlueTooltip;` |
| `classic_era` | `Blizzard_SharedXML/Classic/SharedUIPanelTemplates.lua:759` | identical body |
| `classic_anniversary` | `Blizzard_SharedXMLBase/FrameUtil.lua:277` | identical body |
| `classic_anniversary` | `Blizzard_SharedXML/Classic/SharedUIPanelTemplates.lua:759` | identical body |
| `classic_titan` | `Blizzard_SharedXMLBase/FrameUtil.lua:277` | identical body |
| `classic_titan` | `Blizzard_SharedXML/Classic/SharedUIPanelTemplates.lua:729` | identical body |
| `forever` | `Blizzard_SharedXMLBase/FrameUtil.lua:318` | identical body |
| `live` | `Blizzard_SharedXMLBase/FrameUtil.lua:289` | identical body |

`origin/classic_era:Interface/AddOns/Blizzard_SharedXMLBase/FrameUtil.lua:277-279`

    277	function GetAppropriateTooltip()
    278		return UIParent and GameTooltip or GlueTooltip;
    279	end

`origin/classic_era:Interface/AddOns/Blizzard_SharedXML/Classic/SharedUIPanelTemplates.lua:759-761`

    759	function GetAppropriateTooltip()
    760		return UIParent and GameTooltip or GlueTooltip;
    761	end

`origin/live:Interface/AddOns/Blizzard_SharedXMLBase/FrameUtil.lua:289-291`

    289	function GetAppropriateTooltip()
    290		return UIParent and GameTooltip or GlueTooltip;
    291	end

`origin/forever:Interface/AddOns/Blizzard_SharedXMLBase/FrameUtil.lua:318-320`

    318	function GetAppropriateTooltip()
    319		return UIParent and GameTooltip or GlueTooltip;
    320	end

### 3.2 What it returns, per branch

**VERIFIED — the answer is the same on all five branches.** In an in-game
session `UIParent` is non-nil, so the expression evaluates to the **global
`GameTooltip`** — the shared tooltip. The `GlueTooltip` branch is the
character-select (glue) screen, where `UIParent` does not exist.

**No branch returns anything other than the shared `GameTooltip` in-game.**
The two classic definitions are byte-identical in body, so the duplicate does
not change the result.

**VERIFIED — the `GameTooltip` global is the shared tooltip** on each branch:
`Blizzard_GameTooltip/Classic/GameTooltip.xml:13` (classic family) and
`Blizzard_GameTooltip/Mainline/GameTooltip.xml:249` (forever/live) both
declare `<GameTooltip name="GameTooltip" … parent="UIParent" …>`.

**Note (not a discrepancy):** many other files define a *mixin method*
`X:GetAppropriateTooltip()` (e.g. `CatalogShopMixin:GetAppropriateTooltip`
at `Blizzard_CatalogShop/Blizzard_CatalogShop.lua:167` on `forever`).
Those are `self:` methods on other mixins and are not the global the game
menu calls. The game menu calls the bare global.

---

## 4. Q3 — the restricted call

### 4.1 `C_RestrictedActions.CheckAllowProtectedFunctions`

`origin/classic_era:Interface/AddOns/Blizzard_APIDocumentationGenerated/RestrictedActionsDocumentation.lua:10-26`
(identical on `classic_anniversary` and `classic_titan`; `forever` and `live`
carry one extra field, see below):

    10			{
    11				Name = "CheckAllowProtectedFunctions",
    12				Type = "Function",
    13				SecureHooksAllowed = false,
    14				Documentation = { "Returns true if the calling context has permissions to call protected functions on the supplied object." },
    15	
    16				Arguments =
    17				{
    18					{ Name = "object", Type = "FrameScriptObject", Nilable = false },
    19					{ Name = "silent", Type = "bool", Nilable = false, Default = false, Documentation = { "If true, don't signal blocked action errors if protected function calls are disallowed." } },
    20				},
    21	
    22				Returns =
    23				{
    24					{ Name = "protectedFunctionsAllowed", Type = "bool", Nilable = false },
    25				},
    26			},

`origin/live:…/RestrictedActionsDocumentation.lua:10-27` adds
`SecretArguments = "AllowedWhenUntainted",` at `:14`:

    10			{
    11				Name = "CheckAllowProtectedFunctions",
    12				Type = "Function",
    13				SecureHooksAllowed = false,
    14				SecretArguments = "AllowedWhenUntainted",
    15				Documentation = { "Returns true if the calling context has permissions to call protected functions on the supplied object." },

`origin/forever` is the same as `live` at `:10-27` (the `forever` file's
`ADDON_ACTION_FORBIDDEN` block sits 3 lines lower than classic — see §4.2).

### 4.2 The `ADDON_ACTION_FORBIDDEN` event and its payload

`origin/classic_era:…/RestrictedActionsDocumentation.lua:82-92` (identical on
`classic_anniversary` and `classic_titan`):

    82			{
    83				Name = "AddonActionForbidden",
    84				Type = "Event",
    85				LiteralName = "ADDON_ACTION_FORBIDDEN",
    86				SynchronousEvent = true,
    87				Payload =
    88				{
    89					{ Name = "isTainted", Type = "cstring", Nilable = false },
    90					{ Name = "function", Type = "cstring", Nilable = false },
    91				},
    92			},

`origin/forever:…/RestrictedActionsDocumentation.lua:85-95` and
`origin/live:…/RestrictedActionsDocumentation.lua:85-95` — same block, shifted
by 3 lines (because of the `SecretArguments` line at `:14`):

    85			{
    86				Name = "AddonActionForbidden",
    87				Type = "Event",
    88				LiteralName = "ADDON_ACTION_FORBIDDEN",
    89				SynchronousEvent = true,
    90				Payload =
    91				{
    92					{ Name = "isTainted", Type = "cstring", Nilable = false },
    93					{ Name = "function", Type = "cstring", Nilable = false },
    94				},
    95			},

**VERIFIED — the payload is two `cstring`s: `isTainted` and `function`.**
Both are strings. The operator's message shape
(`AddOn 'TacoTip' tried to call the protected function 'UNKNOWN()'`) matches
this payload: the addon name is the `isTainted` field, and the function name
is the `function` field.

**VERIFIED — `C_RestrictedActions` and `ADDON_ACTION_FORBIDDEN` exist on all
five branches** (grep over `Blizzard_APIDocumentationGenerated/RestrictedActionsDocumentation.lua`
returns `CheckAllowProtectedFunctions` at `:11` and `ADDON_ACTION_FORBIDDEN`
at `:85` on every branch).

### 4.3 `Logout` / `Quit` — engine functions with names

**VERIFIED — the callback creation, per branch.** The `OnClick` closure is
`GenerateMenuCallback`'s returned function; the protected call is the
`callback()` line inside it.

`origin/classic_era:Interface/AddOns/Blizzard_GameMenu/Shared/GameMenuFrame.lua:62-71` and `:157-159`

    62	function GameMenuFrameMixin:InitButtons()
    63		self:Reset();
    64	
    65		local function GenerateMenuCallback(callback, customSoundEffect)
    66			return function()
    67				PlaySound(customSoundEffect or SOUNDKIT.IG_MAINMENU_OPTION);
    68				HideUIPanel(self);
    69				callback();
    70			end;
    71		end
    ...
    157		local exitDisabled = isKioskDisabled or StaticPopup_Visible("CAMP") or StaticPopup_Visible("PLUNDERSTORM_LEAVE") or StaticPopup_Visible("QUIT");
    158		self:AddButton(GameMenuFrameMixin:GetLogoutText(), GenerateMenuCallback(Logout, SOUNDKIT.IG_MAINMENU_LOGOUT), exitDisabled);
    159		self:AddButton(EXIT_GAME, GenerateMenuCallback(Quit, SOUNDKIT.IG_MAINMENU_QUIT), exitDisabled);

| branch | closure | refused call | `Logout` | `Quit` |
|---|---|---|---|---|
| `classic_era` | `:65-71` | `:69` | `:158` | `:159` |
| `classic_anniversary` | `:65-71` | `:69` | `:158` | `:159` |
| `classic_titan` | `:93-99` | `:97` | `:186` | `:187` |
| `forever` | `:164-170` | `:168` | `:263` | `:264` |
| `live` | `:116-122` | `:120` | `:215` | `:216` |

`origin/classic_titan:…/GameMenuFrame.lua:93-99`

     93		local function GenerateMenuCallback(callback, customSoundEffect)
     94			return function()
     95				PlaySound(customSoundEffect or SOUNDKIT.IG_MAINMENU_OPTION);
     96				HideUIPanel(self);
     97				callback();
     98			end;
     99		end

`origin/live:…/GameMenuFrame.lua:116-122` (and `forever:164-170`)

    116		local function GenerateMenuCallback(callback, customSoundEffect)
    117			return function()
    118				PlaySound(customSoundEffect or SOUNDKIT.IG_MAINMENU_OPTION);
    119				HideUIPanel(self);
    120				callback();
    121			end;
    122		end

**VERIFIED — `Logout` and `Quit` are engine (C) functions, and they have
names.** Two independent checks, on all five branches:

1. **No Lua definition exists.** Whole-tree sweep
   (`git grep -nE "^\s*(local\s+)?function\s+(Logout|Quit)\b|^\s*(Logout|Quit)\s*="`
   over `Interface/`) returns **zero hits on every one of the five branches**.
   The identifiers at `GameMenuFrame.lua` are bare global reads.
2. **They are in the generated API docs, as functions.**
   `Blizzard_APIDocumentationGenerated/ConnectionDocumentation.lua:86-93` on
   all five branches:

       86			{
       87				Name = "Logout",
       88				Type = "Function",
       89			},
       90			{
       91				Name = "Quit",
       92				Type = "Function",
       93			},

   The file's header (`ConnectionDocumentation.lua:1-6`) names the namespace:

       1	local Connection =
       2		{
       3			Name = "ConnectionScript",
       4			Type = "System",
       5			Environment = "All",

   `ConnectionScript` is a **global** namespace (not `C_`-prefixed), so the
   engine functions are the bare globals `Logout()` and `Quit()`. The same
   doc file also lists `CancelLogout` (`:10-12`), `ForceLogout` (`:13-15`)
   and `ForceQuit` (`:17-19`).

**Therefore the reporter's `'UNKNOWN()'` is a reporter-side rendering, not
evidence that the refused function is anonymous.** The engine registry has
the names `Logout` and `Quit`; the `function` payload field is a `cstring`
(§4.2) and the reporter's BugGrabber could not resolve it to a display name.
The refused call is still unambiguously `Logout()` (line 158/186/263/215) or
`Quit()` (159/187/264/216), because `GameMenuFrame.lua:69`/`:97`/`:168`/`:120`
is `callback()` and `callback` is bound to exactly one of those two.

**UNKNOWN:** whether the engine's own error text would have said `"Logout"`.
How the engine populates the `function` cstring is engine-side and is not in
the mirror. This does not affect the identification of the refused call.

**Note (not the same function):** the generated docs also contain an
unrelated `Logout` as a `VoiceChatStatusCode` return
(`VoiceChatDocumentation.lua:586`) and as a `QuestSessionResult` enum value
(`QuestSessionConstantsDocumentation.lua:51`). Only
`ConnectionDocumentation.lua:87` is the game-menu one.

---

## 5. Q4 — does Blizzard itself put code in the shared tooltip's script chain?

### 5.1 The answer, per branch

**VERIFIED — on a RELEASE build, no. On a beta/PTR build, yes.**

The only Blizzard code in any of the five trees that hooks the shared
`GameTooltip`'s script chain lives in `Blizzard_PTRFeedback`, and that
addon's `.toc` carries `## OnlyBetaAndPTR: 1` on **all five branches**:

| branch | `Blizzard_PTRFeedback.toc` header |
|---|---|
| `classic_era` | `:2 ## OnlyBetaAndPTR: 1` |
| `classic_anniversary` | `:2 ## OnlyBetaAndPTR: 1` |
| `classic_titan` | `:2 ## OnlyBetaAndPTR: 1` |
| `forever` | `:2 ## OnlyBetaAndPTR: 1` |
| `live` | `:2 ## OnlyBetaAndPTR: 1` |

`origin/classic_era:Interface/AddOns/Blizzard_PTRFeedback/Blizzard_PTRFeedback.toc:1-4`

    1	## Title: PTR Bug Reporter
    2	## OnlyBetaAndPTR: 1
    3	## Notes: Tool for gathering bugs from PTR
    4	## SavedVariables: Blizzard_PTRIssueReporter_Saved

### 5.2 The hooks, quoted

`origin/classic_era:Interface/AddOns/Blizzard_PTRFeedback/Blizzard_PTRFeedback_Tooltips.lua:34-39` — the `OnTooltipSetSpell` hook:

    34	    GameTooltip:HookScript("OnTooltipSetSpell", function(self)
    35	        local name, id = self:GetSpell()
    36	        if (id) then 
    37	            PTR_IssueReporter.HookIntoTooltip(self, PTR_IssueReporter.TooltipTypes.spell, id, name)
    38	        end
    39	    end)

`:81-83` — the `OnTooltipSetItem` hook:

    81	    GameTooltip:HookScript("OnTooltipSetItem", attachItemTooltip)
    82	    ItemRefTooltip:HookScript("OnTooltipSetItem", attachItemTooltip)
    83	end

`:85-96` — the `OnTooltipSetUnit` hook:

    85	function PTR_IssueReporter.SetupUnitTooltips()
    86	    GameTooltip:HookScript("OnTooltipSetUnit", function(self)
    87	        local name, unit = self:GetUnit()
    88	        if (name) and (unit) then
    89	            local guid = UnitGUID(unit) or ""
    90	            local id = tonumber(guid:match("-(%d+)-%x+$"), 10)
    91	            if (id) and (guid:match("%a+") ~= "Player") then
    92	                PTR_IssueReporter.HookIntoTooltip(GameTooltip, PTR_IssueReporter.TooltipTypes.unit, id, name)
    93	            end
    94	        end
    95	    end)
    96	end

`forever`/`live` carry the same addon but reach the data pipeline instead of
the scripts — `Blizzard_PTRFeedback_Tooltips.lua:50`, `:92`, `:120`:

    50		TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Spell, onTooltipSetSpellFunction)
    92		TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, onTooltipSetItemFunction)
    120		TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, onTooltipSetUnitFunction)

**These are Blizzard code, not addon-facing** — but they are Blizzard code
that only runs on a beta/PTR build.

**VERIFIED — the classic `SetupUnitTooltips` hook is dead code on the classic
family.** It calls `self:GetUnit()` (`:87`). The classic `GameTooltipMixin`
has no `GetUnit` (see §6.1), so on a classic beta/PTR build that hook would
raise on the first unit tooltip. This is corroborating evidence that the
PTRFeedback path is not intended to run on the classic clients at all.

### 5.3 The whole-tree `HookScript` census

**VERIFIED — every `HookScript` call site in `Interface/AddOns/`, excluding
the generated API docs:**

| branch | total `HookScript` call sites | sites that touch the shared `GameTooltip` |
|---|---|---|
| `classic_era` | 18 | 3 — all in `Blizzard_PTRFeedback` (`:34`, `:81`, `:86`) |
| `classic_anniversary` | 18 | 3 — same |
| `classic_titan` | 18 | 3 — same |
| `forever` | 40 | 0 on the shared `GameTooltip`; the 5 `GameTooltip`-named ones are `hooksecurefunc` (`:30-32`, `:179`, `:190`) |
| `live` | 29 | 0 on the shared `GameTooltip`; the 5 `GameTooltip`-named ones are `hooksecurefunc` (`:30-32`, `:179`, `:190`) |

The `forever` `hooksecurefunc(GameTooltip, …)` sites are **method** hooks
(`SetUnitAura`, `SetUnitBuff`, `SetUnitDebuff`, `SetCurrencyToken`,
`SetAzeriteEssence`) — a `hooksecurefunc` post-hook does not replace the
method and does not put code in a script chain.

**One more `forever`-only site, checked and dismissed:**
`Blizzard_GamepadActionBars/ActionBarEditFrame.lua:57`

    57		self:GetTooltip():HookScript("OnShow", function(tooltip)
    58			tooltip:SetAlpha(GetCVarBool("GamepadDisableTooltips") and 0 or 1);
    59		end);

`GetTooltip()` there is `GamepadActionBarEditFrameMixin:GetTooltip()`
(`:26-28`), which returns `self.ActionTooltip` — a **dedicated** tooltip
frame, not the shared `GameTooltip`. The shared tooltip is not touched.

### 5.4 The addon-facing hook path

**VERIFIED — the one Blizzard hook mechanism that is explicitly addon-facing
is the Dispatcher, and it can hook the shared tooltip:**

`origin/classic_era:Interface/AddOns/Blizzard_Dispatcher/Blizzard_Dispatcher.lua:384-387`

    384		if (not self.Scripts[frame][script]) then
    385			self.Scripts[frame][script] = {};
    386			frame:HookScript(script, function(...) self:OnScript(frame, script, ...) end);
    387		end

(`forever` and `live` carry the same line at `:386`.) This is how an addon
gets a callback into a Blizzard frame's script chain without touching the
frame itself — and it puts the **addon's** function into the chain.

### 5.5 Script declarations on the shared tooltip

**VERIFIED — per branch, what the shared `GameTooltip` declares.**

*Classic family* — `Blizzard_GameTooltip/Classic/GameTooltip.xml:13-35`
(identical on `classic_era`, `classic_anniversary`, `classic_titan`):

    13		<GameTooltip name="GameTooltip" frameStrata="TOOLTIP" hidden="true" parent="UIParent" inherits="GameTooltipTemplate">
    14			<Scripts>
    15				<OnLoad>
    16					GameTooltip_OnLoad(self);
    17					self.shoppingTooltips = { ShoppingTooltip1, ShoppingTooltip2 };
    18					if (BattlePetTooltip) then
    19						BattlePetTooltip:Hide();
    20					end
    21				</OnLoad>
    22				<OnTooltipSetUnit function="GameTooltip_OnTooltipSetUnit" />
    23				<OnTooltipSetItem function="GameTooltip_OnTooltipSetItem" />
    24				<OnTooltipSetSpell function="GameTooltip_OnTooltipSetSpell" />
    25				<OnHide>
    26					GameTooltip_OnHide(self);
    27					ShoppingTooltip1:Hide();
    28					ShoppingTooltip2:Hide();
    29					if (BattlePetTooltip) then
    30						BattlePetTooltip:Hide();
    31					end
    32				</OnHide>
    33				<OnUpdate function="GameTooltip_OnUpdate"/>
    34			</Scripts>
    35		</GameTooltip>

→ the classic shared `GameTooltip` declares
**`OnTooltipSetUnit`, `OnTooltipSetItem`, `OnTooltipSetSpell`, `OnHide`,
`OnUpdate`, `OnLoad`**, and **NO `OnShow`**.

*Classic template* — `Blizzard_SharedXML/Classic/GameTooltipTemplate.xml:150-156`
(identical on all three classic branches):

    150			<Scripts>
    151				<OnLoad method="OnLoadGameTooltip" inherit="prepend"/>
    152				<OnHide method="OnHide"/>
    153				<OnTooltipSetDefaultAnchor method="OnTooltipSetDefaultAnchor"/>
    154				<OnTooltipAddMoney method="OnTooltipAddMoney"/>
    155				<OnTooltipCleared method="OnTooltipCleared"/>
    156			</Scripts>

→ no `OnShow` on the classic template either. The classic
`GameTooltipCommonTemplate` (`GameTooltipTemplate.xml:3-20`) declares no
scripts at all.

*`forever` / `live`* — `Blizzard_GameTooltip/Mainline/GameTooltip.xml:249-274`
(identical line numbers on both branches):

    249		<GameTooltip name="GameTooltip" inherits="GameTooltipTemplate" parent="UIParent">
    ...
    269			<Scripts>
    270				<OnLoad method="OnLoad"/>
    271				<OnShow function="GameTooltip_OnShow"/>
    272				<OnUpdate function="GameTooltip_OnUpdate"/>
    273			</Scripts>
    274		</GameTooltip>

→ the mainline shared `GameTooltip` declares **`OnShow`, `OnUpdate`,
`OnLoad`**, and **NO `OnHide` on the frame** (the template supplies it) and
**NO `OnTooltipSetUnit` / `OnTooltipSetItem` / `OnTooltipSetSpell`**.

*Mainline template* — `Blizzard_GameTooltip/Mainline/GameTooltip.xml:25-36`
(live) and `:25-36` (forever):

    25			<Scripts>
    26				<OnLoad inherit="prepend" function="GameTooltip_OnLoad"/>
    27				<OnHide function="GameTooltip_OnHide"/>
    28				<OnTooltipSetDefaultAnchor>
    29					GameTooltip_SetDefaultAnchor(self, UIParent);
    30				</OnTooltipSetDefaultAnchor>
    31				<OnTooltipCleared>
    32					GameTooltip_ClearMoney(self);
    33					SharedTooltip_ClearInsertedFrames(self);
    34				</OnTooltipCleared>
    35				<OnEvent method="OnEvent"/>
    36			</Scripts>

The shared base `SharedTooltipTemplate`
(`Blizzard_SharedXML/SharedTooltipTemplates.xml:95-102` on `live`) adds
`OnLoad`/`OnHide`/`OnTooltipSetDefaultAnchor`/`OnTooltipCleared` at `:97-100`.

**VERIFIED — whole-tree sweep for `<OnTooltipSetUnit` / `<OnTooltipSetItem` /
`<OnTooltipSetSpell` script declarations:**

| branch | declarations found |
|---|---|
| `classic_era` | `Blizzard_GameTooltip/Classic/GameTooltip.xml:5, :10, :22, :23, :24, :114`; `Blizzard_UIPanels_Game/Classic/ItemRef.xml:58` |
| `classic_anniversary` | same lines |
| `classic_titan` | same lines |
| `forever` | **none in the entire tree** |
| `live` | **none in the entire tree** |

**This is a hard, branch-qualified fact: on `forever` and `live` the
`OnTooltipSetUnit` / `OnTooltipSetItem` / `OnTooltipSetSpell` scripts do not
exist anywhere in the client tree.** An addon that hooks them on those
clients installs a hook that never fires.

---

## 6. Q5 — the classic-family unit path

### 6.1 `GameTooltipMixin:SetUnit` does not exist on the classic family

**VERIFIED — the question's premise is false for the classic branches.** The
classic `GameTooltipMixin` has exactly five methods, and none of them is
`SetUnit`, `SetItem` or `SetSpell`.

`origin/classic_era:Interface/AddOns/Blizzard_SharedXML/Classic/GameTooltipTemplate.lua:1-23`
(identical on `classic_anniversary` and `classic_titan`):

     1	GameTooltipMixin = {};
     2	
     3	function GameTooltipMixin:OnLoadGameTooltip()
     4		GameTooltip_OnLoad(self);
     5		self.shoppingTooltips = { ShoppingTooltip1, ShoppingTooltip2 };
     6	end
     7	
     8	function GameTooltipMixin:OnHide()
     9		GameTooltip_OnHide(self);
    10	end
    11	
    12	function GameTooltipMixin:OnTooltipSetDefaultAnchor()
    13		GameTooltip_SetDefaultAnchor(self, UIParent);
    14	end
    15	
    16	function GameTooltipMixin:OnTooltipAddMoney(cost, maxCost)
    17		GameTooltip_OnTooltipAddMoney(self, cost, maxCost);
    18	end
    19	
    20	function GameTooltipMixin:OnTooltipCleared()
    21		GameTooltip_ClearMoney(self);
    22		GameTooltip_ClearInsertedFrames(self);
    23	end

The template is instantiated with that mixin at
`Blizzard_SharedXML/Classic/GameTooltipTemplate.xml:22`:

    22		<GameTooltip name="GameTooltipTemplate" clampedToScreen="true" inherits="GameTooltipCommonTemplate, TooltipBackdropTemplate" mixin="GameTooltipMixin" virtual="true">

**VERIFIED — a whole-tree sweep for Lua `SetUnit` definitions on
`classic_era` returns no tooltip at all.** The hits are
`BuffFramePrivateAuraAnchorMixin:SetUnit` (`Blizzard_BuffFrame/BuffFrame.lua:1252`),
`NamePlateAuraItemMixin:SetUnit` / `NamePlateAurasMixin:SetUnit` /
`NamePlateBaseMixin:SetUnit` / `NamePlateClassificationFrameMixin:SetUnit` /
`NamePlateHealthBarMixin:SetUnit` (`Blizzard_NamePlates/…`),
`PlayerLocationMixin:SetUnit` (`Blizzard_ObjectAPI/Classic/PlayerLocation.lua:83`),
`SpellDiminishStatusTrayMixin:SetUnit`
(`Blizzard_SpellDiminishUI/Blizzard_SpellDiminishUITemplates.lua:71`),
`CastingMixin:SetUnit` (`Blizzard_UIPanels_Game/Shared/CastingBarFrame.lua:213`),
and one **table entry**, not a function —
`Blizzard_SharedXMLGame/Tooltip/TooltipDataHandler.lua:582` (`SetUnit = "GetUnit",`,
inside the accessor map, §7).

→ **On the classic family `GameTooltip:SetUnit(...)` is an ENGINE method**,
in the same class as `GameTooltip.FadeOut`. Blizzard calls it unguarded:

`origin/classic_era:Interface/AddOns/Blizzard_UnitFrame/Classic/UnitFrame.lua:451-457`

    451	function UnitFrame_UpdateTooltip (self)
    452		GameTooltip_SetDefaultAnchor(GameTooltip, self);
    453		if ( GameTooltip:SetUnit(self.unit, self.hideStatusOnTooltip) ) then
    454			self.UpdateTooltip = UnitFrame_UpdateTooltip;
    455		else
    456			self.UpdateTooltip = nil;
    457		end

**VERIFIED — the classic `GameTooltip` also has no `GetUnit`.** The engine
method that identifies the tooltip's unit is `IsUnit`, used by
`GameTooltip_OnTooltipSetUnit` below. This corroborates `workshop.md`'s
standing note that "the classic-family unit tooltip is not the modern one".

### 6.2 The classic `OnTooltipSetUnit` / `OnTooltipSetItem` / `OnTooltipSetSpell` implementations

`origin/classic_era:Interface/AddOns/Blizzard_GameTooltip/Classic/GameTooltip.lua:498-530`
(identical on `classic_anniversary` and `classic_titan`):

    498	function GameTooltip_OnTooltipSetUnit(self)
    499		if self:IsUnit("mouseover") then
    500			self:GetLeftLine(1):SetTextColor(GameTooltip_UnitColor("mouseover"));
    501		end
    502		GameTooltip_HideBattlePetTooltip();
    503	end
    504	
    505	function GameTooltip_UpdateStyle(self)
    506		local backdropStyle = nil;
    507		SharedTooltip_SetBackdropStyle(self, backdropStyle);
    508	end
    509	
    510	function GameTooltip_OnTooltipSetItem(self)
    511		if IsModifiedClick("COMPAREITEMS") or (GetCVarBool("alwaysCompareItems") and not self:IsEquippedItem()) then
    512			GameTooltip_ShowCompareItem(self);
    513		else
    514			GameTooltip_HideShoppingTooltips(self);
    515		end
    516		GameTooltip_HideBattlePetTooltip();
    517	
    518		GameTooltip_UpdateStyle(self);
    519	end
    520	
    521	function GameTooltip_OnTooltipSetShoppingItem(self)
    522		GameTooltip_UpdateStyle(self);
    523	end
    524	
    525	function GameTooltip_OnTooltipSetSpell(self)
    526		if (not IsModifiedClick("COMPAREITEMS") and not GetCVarBool("alwaysCompareItems")) or not GameTooltip_ShowCompareSpell(self) then
    527			GameTooltip_HideShoppingTooltips(self);
    528		end
    529		GameTooltip_HideBattlePetTooltip();
    530	end

### 6.3 What an addon hooking those scripts gets called with

**VERIFIED — on the classic family, the addon callback receives exactly one
argument: the tooltip frame itself.**

- `GameTooltip_OnTooltipSetUnit(self)` — the only parameter is `self`.
- `GameTooltip_OnTooltipSetItem(self)` — only `self`.
- `GameTooltip_OnTooltipSetSpell(self)` — only `self`.
- The XML wiring passes no extra argument:
  `<OnTooltipSetUnit function="GameTooltip_OnTooltipSetUnit" />`
  (`GameTooltip.xml:22`).

So `HookScript("OnTooltipSetUnit", function(self) … end)` on the classic
family is called with **the tooltip frame and nothing else**. There is no
unit token, no item link, no spell id in the argument list. The unit is only
reachable indirectly (`self:IsUnit("mouseover")`, or `UnitGUID("mouseover")`).

**VERIFIED — the call is from plain insecure code, not from a
`SecureCall`/`securecall` context.** The chain is:

    Blizzard_UnitFrame/Classic/UnitFrame.lua:453   GameTooltip:SetUnit(self.unit, self.hideStatusOnTooltip)
      -> (engine method) fires the frame's "OnTooltipSetUnit" script
        -> Blizzard_GameTooltip/Classic/GameTooltip.lua:498  GameTooltip_OnTooltipSetUnit(self)
          -> (any addon HookScript callback on the same script)

`GameTooltip_OnTooltipSetUnit` contains no `securecall`, no `securecallfunction`,
no `forceinsecure` and no `CreateSecureDelegate`; it is ordinary Lua executed
in the engine's normal script dispatch. The same holds for
`GameTooltip_OnTooltipSetItem` (`:510`) and `GameTooltip_OnTooltipSetSpell`
(`:525`).

**VERIFIED — the addon callback therefore runs in the same insecure context
as Blizzard's own handler.** There is no `SecureCall` wrapper on the classic
path to strip or contain taint for the addon callback.

---

## 7. Q6 — is there a secure dispatch for the classic tooltip?

### 7.1 The machinery exists in the classic tree

**VERIFIED — `Blizzard_SharedXMLGame/Tooltip/TooltipDataHandler.lua` is
present in the classic trees** (610 lines on `classic_era`), and it contains
the full secure attribute-delegate dispatch, byte-for-byte the same shape as
the mainline one.

`origin/classic_era:Interface/AddOns/Blizzard_SharedXMLGame/Tooltip/TooltipDataHandler.lua:8-12`

     8	local canaccessallvalues = canaccessallvalues;
     9	local forceinsecure = forceinsecure;
    10	local issecure = issecure;
    11	local CheckAllowProtectedFunctions = C_RestrictedActions.CheckAllowProtectedFunctions;
    12	local SafePack = SafePack;

`:111-125` — the attribute delegate:

    111	local AttributeDelegate = CreateFrame("FRAME");
    112	AttributeDelegate:SetForbidden();
    113	AttributeDelegate:SetScript("OnAttributeChanged", function(self, attribute, value)
    114		local callTable = InsertCallbackTables[attribute];
    115		if callTable then
    116			local keyType, func = securecallfunction(unpack, value);
    117			InternalAddCall(callTable, keyType, func);
    118		end
    119	
    120		local processTable = ProcessCallbackTables[attribute];
    121		if processTable then
    122			local argCount = securecallfunction(rawget, value, "n");
    123			AttributeDelegate:SetAttribute(ProcessCallbackResultAttribute, ProcessInsecureCalls(processTable, securecallfunction(unpack, value, 1, argCount)));
    124		end
    125	end);

`:181-209` — the registration entry point:

    181	local function AddCall(callType, keyType, func)
    182		if issecure() then
    183			local tbl = secureTables[callType];
    184			InternalAddCall(tbl, keyType, func);
    185		else
    186			local tbl = insecureTables[callType];
    187			local function InsecureCallback(...)
    188				forceinsecure();
    189				return func(...);
    190			end
    191			AttributeDelegate:SetAttribute(InsertCallbackAttributes[tbl], { keyType, InsecureCallback });
    192		end
    193	end
    194	
    195	function TooltipDataProcessor.AddTooltipPreCall(tooltipType, func)
    196		AddCall("tooltipPreCall", tooltipType, func);
    197	end
    198	
    199	function TooltipDataProcessor.AddTooltipPostCall(tooltipType, func)
    200		AddCall("tooltipPostCall", tooltipType, func);
    201	end
    202	
    203	function TooltipDataProcessor.AddLinePreCall(lineType, func)
    204		AddCall("linePreCall", lineType, func);
    205	end
    206	
    207	function TooltipDataProcessor.AddLinePostCall(lineType, func)
    208		AddCall("linePostCall", lineType, func);
    209	end

`TooltipDataHandlerMixin` is defined at `:239`, with `IsTooltipType` at `:418`
and `GetPrimaryTooltipData` at `:408`.

### 7.2 …but on `classic_era` it is not even loaded

**VERIFIED — the TOC excludes it from the vanilla game type.**
`origin/classic_era:Interface/AddOns/Blizzard_SharedXMLGame/Blizzard_SharedXMLGame.toc:1-16`
(byte-identical on `classic_anniversary` and `classic_titan`):

     1	## Title: Blizzard_SharedXMLGame
     2	## Dep: Blizzard_SharedXML
     3	## Dep: Blizzard_Colors
     4	## AllowLoad: Game
     5	Shared\Localization.lua
     6	[Family]\Localization.lua [AllowLoadGameType mainline]
     7	[Game]\Localization.lua [AllowLoadGameType vanilla]
     8	Tooltip\TooltipUtil.lua [AllowLoadGameType mainline]
     9	Tooltip\TooltipDataHandler.lua [ExcludeLoadGameType vanilla]
    10	Tooltip\TooltipDataRules.lua [AllowLoadGameType mainline]
    11	Tooltip\TooltipComparisonManager.lua [AllowLoadGameType mainline]
    12	StaticModelInfo.lua [AllowLoadGameType mainline]
    13	DressUpModelFrameMixin.lua [AllowLoadGameType mainline]
    14	[Family]\ListTemplates.lua [AllowLoadGameType mainline]
    15	[Family]\ListTemplates.xml [AllowLoadGameType mainline]
    16	CompactUnitFramesConstants.lua

`origin/forever:…/Blizzard_SharedXMLGame.toc:9` is the **unfiltered** line
`Tooltip\TooltipDataHandler.lua` — it loads on every game type.

The per-game-type selection is visible in the same trees:
`Blizzard_FrameXMLBase/Blizzard_FrameXMLBase_Vanilla.toc:6` →
`## AllowLoadGameType: vanilla`; `_TBC.toc:6` → `tbc`; `_Wrath.toc:6` →
`wrath`; `_Cata.toc:6` → `cata`; `_Mists.toc:6` → `mists`;
`_Mainline.toc` carries no `AllowLoadGameType` line.

### 7.3 The per-branch verdict

| branch | game type | `TooltipDataHandler.lua` loads? | `TooltipDataProcessor` global exists? | shared `GameTooltip` uses the data pipeline? | **secure dispatch for the shared tooltip?** |
|---|---|---|---|---|---|
| `classic_era` | `vanilla` | **NO** — `[ExcludeLoadGameType vanilla]` | **NO** | no | **NO** |
| `classic_anniversary` | `cata` | yes | yes | **no** — classic tooltip has `mixin="GameTooltipMixin"` only | **NO** (machinery present, not wired to the shared tooltip) |
| `classic_titan` | `mists` | yes | yes | **no** — same | **NO** (same) |
| `forever` | `mainline` | yes | yes | **YES** | **YES** |
| `live` | `mainline` | yes | yes | **YES** | **YES** |

**VERIFIED — the mainline shared tooltip IS wired to the data pipeline.**
`origin/live:Interface/AddOns/Blizzard_GameTooltip/Mainline/GameTooltip.xml:4`

     4		<GameTooltip name="GameTooltipTemplate" mixin="GameTooltipDataMixin" inherits="SharedTooltipTemplate" virtual="true">

`origin/live:Interface/AddOns/Blizzard_GameTooltip/Mainline/GameTooltip.lua:951`
(same statement on `origin/forever` at
`Interface/AddOns/Blizzard_GameTooltip/Mainline/GameTooltip.lua:960`)

    951	GameTooltipDataMixin = CreateFromMixins(TooltipDataHandlerMixin);

and the mainline tooltip exposes the modern getters the classic one lacks
(`live`: `Mainline/GameTooltip.lua:1027-1037`; `forever`:
`Mainline/GameTooltip.lua:1036-1046`):

   1027	function GameTooltipDataMixin:GetItem()
   1028		return TooltipUtil.GetDisplayedItem(self);
   1029	end
   1030	
   1031	function GameTooltipDataMixin:GetSpell()
   1032		return TooltipUtil.GetDisplayedSpell(self);
   1033	end
   1034	
   1035	function GameTooltipDataMixin:GetUnit()
   1036		return TooltipUtil.GetDisplayedUnit(self);
   1037	end

(the same three getters exist on `origin/forever` at
`Mainline/GameTooltip.lua:1036` / `:1040` / `:1044`)

**VERIFIED — the classic shared tooltip is NOT wired to it**, on any of the
three classic branches: the template's mixin is the 5-method
`GameTooltipMixin` (§6.1) and the concrete frame declares only the three
`OnTooltipSet*` script handlers (§5.5).

**VERIFIED — the closest thing to a secure dispatch on the classic family
is the `CreateSecureDelegate` accessor table**, which the classic
`TooltipDataHandler.lua` also carries (`:447-519`, accessor map at `:521-604`
including `SetUnit = "GetUnit",` at `:582`). But it lives in the
data-handler mixin, which the classic shared `GameTooltip` does not mix in.
On `classic_era` the file is not loaded at all.

**VERIFIED — nothing on the classic family calls
`TooltipDataProcessor.AddTooltipPostCall` for the shared tooltip.** The only
callers in the classic trees are in `Blizzard_SharedXMLGame/Tooltip/TooltipDataRules.lua`
(19 call sites, e.g. `:140`, `:141`, `:177`, `:190`, `:212`, `:228`) — and that
file is `[AllowLoadGameType mainline]`, so it does not load on the classic
branches either. On `forever`/`live` the same rules file is joined by the
three `Blizzard_PTRFeedback` sites (`Blizzard_PTRFeedback_Tooltips.lua:50`,
`:92`, `:120`), which are beta/PTR only (§5.1).

### 7.4 `forceinsecure`

**VERIFIED — `forceinsecure` has NO Lua definition in any of the five
trees.** It is an engine global. Whole-tree grep finds only *call sites* and
the local capture at `TooltipDataHandler.lua:9`
(`local forceinsecure = forceinsecure;`).

**VERIFIED — it is absent from the generated API docs on all five branches**
(`git grep -n "Name = \"forceinsecure\"" … -- Interface/AddOns/Blizzard_APIDocumentationGenerated/`
returns nothing on every branch). Same for `securecall`. These are engine
globals that the generated docs do not describe — the same situation as
`GameTooltip.FadeOut`.

**VERIFIED — the complete list of `forceinsecure(` call sites inside the
tooltip code:**

| branch | call site in tooltip code |
|---|---|
| `classic_era` | `Blizzard_SharedXMLGame/Tooltip/TooltipDataHandler.lua:188` |
| `classic_anniversary` | `Blizzard_SharedXMLGame/Tooltip/TooltipDataHandler.lua:188` |
| `classic_titan` | `Blizzard_SharedXMLGame/Tooltip/TooltipDataHandler.lua:188` |
| `forever` | `Blizzard_SharedXMLGame/Tooltip/TooltipDataHandler.lua:188` |
| `live` | `Blizzard_SharedXMLGame/Tooltip/TooltipDataHandler.lua:188` |

(Quoted at `:188` in §7.1.) The only other `forceinsecure(` inside
`Blizzard_SharedXML/**` is `Blizzard_SharedXML/Dump.lua:446`, which is a
debug dumper, not tooltip logic. There is **no** `forceinsecure(` call
anywhere in `Blizzard_GameTooltip/**` on any branch.

---

## 8. Q7 — the mover / anchor path

### 8.1 The two definitions

**VERIFIED — the classic family has TWO `GameTooltip_SetDefaultAnchor`
definitions with the same name; `forever`/`live` have one.**

`origin/classic_era:Interface/AddOns/Blizzard_GameTooltip/Classic/GameTooltip.lua:109-113`

   109	function GameTooltip_SetDefaultAnchor(tooltip, parent)
   110		tooltip:SetOwner(parent, "ANCHOR_NONE");
   111		tooltip:SetPoint("BOTTOMRIGHT", "UIParent", "BOTTOMRIGHT", -CONTAINER_OFFSET_X - 13, CONTAINER_OFFSET_Y);
   112		tooltip.default = 1;
   113	end

`origin/classic_era:Interface/AddOns/Blizzard_SharedXML/SharedTooltipTemplates.lua:87-…`
(the same file/line on all five branches):

    87	function GameTooltip_SetDefaultAnchor(tooltip, parent)
    88		tooltip:SetOwner(parent, "ANCHOR_NONE");
    89	
    90		local point, relativeTo, relativePoint, offsetX, offsetY = SharedTooltipDefaultContainer:GetPoint(1);
    91		--If GameTooltipDefaultContainer exists, use that instead
    92		if GameTooltipDefaultContainer then
    93			point, relativeTo, relativePoint, offsetX, offsetY = GameTooltipDefaultContainer:GetPoint(1);
    94		end

The two bodies differ: the classic `Blizzard_GameTooltip` one anchors to a
fixed `UIParent` corner and sets `tooltip.default = 1`; the shared one reads
`GameTooltipDefaultContainer`'s anchor point. Again, load order decides
which one is live on the classic branches.

**VERIFIED — a third, distinct anchor helper exists on the mainline:**
`SharedTooltip_SetDefaultAnchor` at
`Blizzard_SharedXML/SharedTooltipTemplates.lua:33-36` (live and forever):

    33	function SharedTooltip_SetDefaultAnchor(tooltip, parent)
    34		tooltip:SetOwner(parent or GetAppropriateTopLevelParent(), "ANCHOR_NONE");
    35		tooltip:SetPoint("BOTTOMRIGHT", GetAppropriateTopLevelParent(), "BOTTOMRIGHT", DEFAULT_TOOLTIP_OFFSET_X, DEFAULT_TOOLTIP_OFFSET_Y);
    36	end

It is wired as the template's `OnTooltipSetDefaultAnchor` script on `live`
(`Blizzard_SharedXML/SharedTooltipTemplates.xml:99`).

### 8.2 Who calls it

**VERIFIED — the call sites, by owner.** (Full lists were swept per branch;
the shapes below are the same on the three classic branches and on
forever/live, with different line numbers.)

*Unit frames (yes):*
- classic: `Blizzard_UnitFrame/Classic/UnitFrame.lua:430`, `:434`, `:452`
  (the latter inside `UnitFrame_UpdateTooltip`, §6.1);
  `Blizzard_UnitFrame/Classic/PlayerFrame.lua:566`;
  `Blizzard_UnitFrame/Classic/UnitPowerBarAlt.lua:49`
- `forever`: `Blizzard_UnitFrame/Mainline/UnitFrame.lua:397`,
  `Blizzard_UnitFrame/Mainline/UnitPowerBarAlt.lua:49`
- `live`: `Blizzard_UnitFrame/Mainline/UnitFrame.lua:390`,
  `Blizzard_UnitFrame/Mainline/UnitPowerBarAlt.lua:49`

*Item / character frames (yes):*
- classic: `Blizzard_CharacterFrame/Wrath/PaperDollFrame.lua:2249`,
  `Blizzard_CharacterFrame/Cata/PaperDollFrame.lua:3427`,
  `Blizzard_CharacterFrame/Wrath/PetPaperDollFrame.lua:238`
- `forever`: `Blizzard_UIPanels_Game/Mainline/PaperDollFrame.lua:2423`,
  `Blizzard_UIPanels_Game/Camelot/PaperDollFrame.lua:2690`
- `live`: `Blizzard_UIPanels_Game/Mainline/PaperDollFrame.lua:2172`

*Action buttons (yes):* `Blizzard_ActionBar/Shared/ActionButton.lua:1104`
(classic) / `:1117` (forever) / `:1073` (live); plus `PetActionBar`,
`PossessActionBar`, `SpellFlyout`, `StanceBar`, `MultiCastActionBarFrame`,
`ExpBarOverrides`, `ArtifactBar`, `AzeriteBar`.

*Other frames (yes):* minimap, raid UI, name plates, vehicle seat indicator,
achievement UI, auction UI, cooldown viewer, damage meter, encounter
timeline/warnings, performance bar, model scene control frame.

*The game menu (NO).* **VERIFIED — there is no game-menu call site.** A
whole-tree sweep for `GameTooltip_SetDefaultAnchor` returns, on every one of
the five branches, only: the definitions themselves, the unit-frame/item-frame
/action-button/UI call sites listed above, and
`Blizzard_SharedXML/Classic/GameTooltipTemplate.lua:13`
(`GameTooltipMixin:OnTooltipSetDefaultAnchor` → `GameTooltip_SetDefaultAnchor(self, UIParent)`).
No hit under `Interface/AddOns/Blizzard_GameMenu/` on any branch.

### 8.3 Does the game-menu path reach the anchor helper?

**VERIFIED — NO, on every branch.** The game menu's tooltip path is
`GetAppropriateTooltip()` → `SetOwner(newButton, "ANCHOR_RIGHT")` →
`SetText` → `AddLine` → `Show()` (§2.2). `SetOwner` with `"ANCHOR_RIGHT"`
anchors the tooltip to the button; it does **not** call
`GameTooltip_SetDefaultAnchor` and does **not** fire the
`OnTooltipSetDefaultAnchor` script.

**VERIFIED — the `OnTooltipSetDefaultAnchor` script is a separate
mechanism**, fired by the engine when the tooltip's default anchor is
requested, and handled by:
- classic: `GameTooltipMixin:OnTooltipSetDefaultAnchor` →
  `GameTooltip_SetDefaultAnchor(self, UIParent)`
  (`Blizzard_SharedXML/Classic/GameTooltipTemplate.lua:12-14`, wired at
  `GameTooltipTemplate.xml:153`)
- mainline: `GameTooltip.xml:28-30` → `GameTooltip_SetDefaultAnchor(self, UIParent);`
  (live and forever), and `SharedTooltipTemplates.xml:99` →
  `SharedTooltip_SetDefaultAnchor` on the shared base template.

**So the game menu and the anchor/mover path are two separate mechanisms
that meet only on the shared `GameTooltip` object.** The menu does not reach
`GameTooltip_SetDefaultAnchor`; the mover's hook on
`GameTooltip_SetDefaultAnchor` therefore does not sit in the game menu's
own call chain.

---

## 9. Per-branch comparison

| question | `classic_era` | `classic_anniversary` | `classic_titan` | `forever` | `live` |
|---|---|---|---|---|---|
| menu-button tooltip calls (in order) | `GetAppropriateTooltip` `:39` → `SetOwner` `:40` → `SetText` `:41` → `GameTooltip_AddErrorLine` `:42` → `Show` `:43`; OnLeave `GetAppropriateTooltip():Hide()` `:47` | same lines | same lines | `:47`→`:48`→`:49`→`:50`→`:51`; OnLeave `:55` | same as forever |
| menu handlers installed only for disabled buttons? | yes (`MainMenuFrameTemplates.lua:37`) | yes | yes | yes (`:45`) | yes |
| `GetAppropriateTooltip` global definitions | **2** (`FrameUtil.lua:277`, `SharedUIPanelTemplates.lua:759`) | **2** (`:277`, `:759`) | **2** (`:277`, `:729`) | 1 (`FrameUtil.lua:318`) | 1 (`FrameUtil.lua:289`) |
| returns the shared `GameTooltip` in-game? | yes | yes | yes | yes | yes |
| `Logout` / `Quit` are engine functions? | yes (`ConnectionDocumentation.lua:86-93`) | yes | yes | yes | yes |
| `Logout` / `Quit` call sites | `GameMenuFrame.lua:158`/`:159` | `:158`/`:159` | `:186`/`:187` | `:263`/`:264` | `:215`/`:216` |
| refused call line (`callback()`) | `:69` | `:69` | `:97` | `:168` | `:120` |
| shared `GameTooltip` declares `OnShow`? | **NO** | **NO** | **NO** | **YES** (`GameTooltip.xml:271`) | **YES** (`:271`) |
| shared `GameTooltip` declares `OnHide`? | yes (`:25`) | yes | yes | yes (template `:27`) | yes (template `:27`) |
| shared `GameTooltip` declares `OnTooltipSetUnit`? | **YES** (`:22`) | **YES** | **YES** | **NO** (nowhere in tree) | **NO** (nowhere in tree) |
| shared `GameTooltip` declares `OnTooltipSetItem` / `OnTooltipSetSpell`? | yes (`:23` / `:24`) | yes | yes | **NO** | **NO** |
| Blizzard hooks the shared tooltip's scripts (release build)? | **NO** (only `Blizzard_PTRFeedback`, `OnlyBetaAndPTR`) | **NO** | **NO** | **NO** | **NO** |
| `GameTooltipMixin:SetUnit` in the tree? | **NO** (engine method) | **NO** | **NO** | `GameTooltipDataMixin` (not a `GameTooltipMixin`) | `GameTooltipDataMixin` |
| addon hook on `OnTooltipSetUnit` is called with | `(tooltip)` only, insecure | same | same | n/a (script absent) | n/a (script absent) |
| `TooltipDataHandler.lua` loaded? | **NO** (`[ExcludeLoadGameType vanilla]`) | yes | yes | yes | yes |
| secure attribute-delegate dispatch for the shared tooltip? | **NO** | **NO** (machinery present, not wired) | **NO** (machinery present, not wired) | **YES** | **YES** |
| `forceinsecure(` in tooltip code | 1 (`TooltipDataHandler.lua:188`) | 1 (`:188`) | 1 (`:188`) | 1 (`:188`) | 1 (`:188`) |
| `GameTooltip_SetDefaultAnchor` definitions | **2** (`Blizzard_GameTooltip/Classic/GameTooltip.lua:109`, `SharedTooltipTemplates.lua:87`) | **2** (same) | **2** (same) | 1 (`SharedTooltipTemplates.lua:87`) | 1 (`:87`) |
| game menu calls `GameTooltip_SetDefaultAnchor`? | **NO** | **NO** | **NO** | **NO** | **NO** |
| unit frames call it? | yes (`UnitFrame.lua:430,434,452`) | yes | yes | yes (`UnitFrame.lua:397`) | yes (`UnitFrame.lua:390`) |

---

## 10. Corrections to standing knowledge

1. **`bench/audits/2026-10-20-quit-taint.md` §1 — "`Logout` and `Quit` are
   engine (C) functions — hence `'UNKNOWN()'`."**
   → **Right that they are engine functions; wrong about the "hence".**
   `Logout` and `Quit` are **named** engine functions: they are documented
   as `Type = "Function"` in the `ConnectionScript` namespace at
   `Blizzard_APIDocumentationGenerated/ConnectionDocumentation.lua:86-93` on
   all five branches. The reporter's `'UNKNOWN()'` is a failure of *their*
   name resolution of the `function` cstring payload
   (`RestrictedActionsDocumentation.lua:89-90`), not evidence that the
   protected function is anonymous. The identification of the refused call
   as `Logout()`/`Quit()` is unaffected.

2. **`bench/audits/2026-10-20-quit-taint.md` §3 — "`GetAppropriateTooltip()`
   returns the shared tooltip on every branch:
   `origin/classic_era:…/FrameUtil.lua:277-279` … `origin/live:…/FrameUtil.lua:289-291`."**
   → **Incomplete.** On the classic family there are **two** global
   definitions of `GetAppropriateTooltip`:
   `Blizzard_SharedXMLBase/FrameUtil.lua:277` **and**
   `Blizzard_SharedXML/Classic/SharedUIPanelTemplates.lua:759`
   (`:729` on `classic_titan`). The bodies are identical, so the conclusion
   (the shared `GameTooltip`) stands, but the definition is duplicated on
   the classic branches and the prior audit cited only one of them.

3. **`bench/audits/2026-10-20-quit-taint.md` §4 ("the classic-only
   difference") — "On the classic family there is no secure dispatch for the
   classic tooltip."**
   → **The conclusion is right; the reason given is not the strongest one,
   and the prior text is misleading in one specific way.** The prior audit
   justified it by the classic template's mixin
   (`mixin="GameTooltipMixin"`, no `IsTooltipType`). That part is correct
   (§6.1, §7.3). But the prior audit quoted
   `origin/classic_era:…/Tooltip/TooltipDataHandler.lua:181-201` — the
   `AddCall` body — as if it were live on the classic client. That file is
   **`[ExcludeLoadGameType vanilla]`** in
   `Blizzard_SharedXMLGame.toc:9`, so on `classic_era` it is **not loaded at
   all** and the global `TooltipDataProcessor` does not exist there. On
   `classic_anniversary` (`cata`) and `classic_titan` (`mists`) the file
   **does** load, but the classic shared `GameTooltip` still does not mix in
   `TooltipDataHandlerMixin`, so the dispatch is present-but-unwired there.

4. **`bench/audits/2026-10-20-quit-taint.md` §4, row T5 — "live/forever (the
   classic `GameTooltip` declares no `OnShow`)."**
   → **VERIFIED and additionally sharpened.** Correct on the classic family.
   The new fact is the converse: on `forever` and `live` the classic-style
   `OnTooltipSetUnit` / `OnTooltipSetItem` / `OnTooltipSetSpell` scripts
   **do not exist anywhere in the tree** (whole-tree sweep for
   `<OnTooltipSetUnit` / `<OnTooltipSetItem` / `<OnTooltipSetSpell`), so
   those hooks are inert on mainline.

5. **`workshop.md` → "what the client actually does"** — its bullet
   *"the classic-family unit tooltip is not the modern one. it has no
   `GetUnit`, no `TooltipUtil` and no `owner.unit`; blizzard identifies it
   with `IsUnit`"*.
   → **VERIFIED, and now with the mechanism pinned.** `IsUnit` is used at
   `Blizzard_GameTooltip/Classic/GameTooltip.lua:499`; the classic
   `GameTooltipMixin` has no `GetUnit` (§6.1) and
   `Blizzard_SharedXMLGame/Tooltip/TooltipUtil.lua` is
   `[AllowLoadGameType mainline]`, i.e. absent on the classic family. The
   prior audit did not state that on the classic family
   **`GameTooltip:SetUnit` is itself an engine method** (no Lua definition
   anywhere in the tree), which is why `UnitFrame.lua:453` can call it
   unguarded.

6. **New standing fact, not previously recorded anywhere on the bench:**
   the classic family carries **three** same-named duplicate helper
   definitions — `GetAppropriateTooltip` (2), `GameTooltip_AddErrorLine`
   (2), `GameTooltip_SetDefaultAnchor` (2). Anyone grepping the classic
   tree for "the" definition of any of these will find two, and the
   load-order winner is not obvious from the file names.

---

## 11. What I could not establish

1. **The taint-propagation rule itself.** The FrameXML mirror carries no
   engine code. Nothing here asserts how taint moves from the shared
   `GameTooltip` to the GameMenu's Logout button, or that it does. The two
   rules the chain needs are stated by Blizzard in prose (quoted in the
   prior audit), but the hop itself is **ASSUMED**. What would verify it: an
   in-game A/B on the operator's client (tooltip hooks disabled → try to log
   out), plus the engine-side taint rules, which are not in the mirror.

2. **Whether the `Blizzard_PTRFeedback` hooks are present on the operator's
   client.** `## OnlyBetaAndPTR: 1` means the addon is not loaded on a
   release build; the operator's Classic Era client is a release build, so
   the answer should be "not loaded", but the mirror does not record which
   build the operator ran.

3. **Whether the operator's error's `'UNKNOWN()'` string came from the
   engine's payload or from the reporter's own formatter.** The payload
   field is a `cstring` and the engine's filling of it is engine-side. The
   *identity* of the refused call is not in doubt (§4.3); the exact string
   is.

4. **Which `GameTooltip_SetDefaultAnchor` is live on the classic branches.**
   Both definitions exist (§8.1); which one wins depends on the TOC load
   order of `Blizzard_GameTooltip` vs `Blizzard_SharedXML`, and the two
   bodies differ in their anchor point and in whether they set
   `tooltip.default = 1`. The mirror carries the TOCs but the effective
   order for a given build is engine-side. The same applies to the
   duplicated `GetAppropriateTooltip` and `GameTooltip_AddErrorLine` (whose
   bodies happen to agree).

5. **The exact per-build game type of `classic_anniversary` and
   `classic_titan`.** The trees carry `vanilla`/`tbc`/`wrath`/`cata`/`mists`/
   `mainline` TOC variants and the branch names imply `cata` and `mists`;
   the branch's own build marker was not read. This matters only for the
   "does `TooltipDataHandler.lua` load" cell in §7.3, and the answer there
   ("yes") holds for every non-`vanilla` game type.

6. **Whether the game menu is the only consumer of the shared tooltip in
   the Logout flow.** The shared `GameTooltip` is a child of `UIParent` and
   the GameMenu is a child of `UIParent`; whether the engine's protected-call
   check consults the tainted *button*, the *menu frame*, or a global flag
   is engine-side and not in the mirror.

7. **No in-game observation was available for any of the five branches.**
   Every claim in this artifact is source-derived. Nothing here is a
   statement about what a player sees.

---

## 12. Validation

1. **Mirror unchanged.** `git -C /home/sam/wow-ui-source status --porcelain`
   returns the same three pre-existing untracked entries as before this desk
   started (`?? .vscode/`, `?? SKILL.md`, `?? reference/`) — a byte-identical
   before/after diff. `git -C /home/sam/wow-ui-source diff --stat` and
   `diff --cached --stat` are both empty: no tracked file modified, nothing
   staged. The mirror's `HEAD` is `8165d4cd6` and its reflog shows the last
   state-changing git operation was a
   `checkout: moving from classic_anniversary to classic_era` at
   **2026-10-14 10:51:26 -0400** — a week before this desk ran. No
   state-changing git command was issued against the mirror.
2. **Every quote was produced by a `git show` / `git grep` / `git ls-tree`
   actually run** against `origin/<branch>` in this session; each carries
   its `path:line`.
3. **Every branch-specific claim names its branch**, in the prose and in the
   §9 table.
4. **No product file was touched.** `git -C /home/sam/TacoTip-Gearscore-TBC
   status --short` shows only the additions of this desk
   (`desks/taint-client-source-2026-10-21/`) and this artifact
   (`bench/audits/2026-10-21-gamemenu-tooltip-coupling.md`) relative to the
   pre-existing (intentionally uncommitted) tree state.
