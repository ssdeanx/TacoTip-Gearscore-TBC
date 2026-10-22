# Anchor client truth — per-branch verification of the tooltip anchor machinery

Lane: desk `anchor-client-truth`, 2026-10-22. READ-ONLY on `/home/sam/wow-ui-source`.
Branches checked in order: **classic_anniversary FIRST** (operator branch — can withdraw any claim),
then classic_era (operator's second branch), then classic_titan, `remotes/origin/forever`
(local branch `forever` does not exist; `git show forever:...` fails), origin/live.
Method: `git show <branch>:<path>` + `git diff --ignore-cr-at-eol` between branches
(raw diffs between anniversary and era were pure CRLF noise; ignore-CR diff is the content truth).

---

## classic_anniversary (operator branch — checked first)

### (a) GameTooltip_SetDefaultAnchor

Two Lua definitions exist on this branch. Load order decides which wins:

- `Interface/AddOns/Blizzard_SharedXML/SharedTooltipTemplates.lua:87` — the shared one.
- `Interface/AddOns/Blizzard_GameTooltip/Classic/GameTooltip.lua:109` — the Classic override.

Dependency chain proving the Classic override loads LAST and wins:

- `Blizzard_GameTooltip_Classic.toc`: `## Dependencies: Blizzard_UIParent`
- `Blizzard_UIParent_TBC.toc`: `## Dependencies: Blizzard_FrameXMLBase, Blizzard_ObjectAPI`
- `Blizzard_FrameXMLBase_TBC.toc`: `## Dependencies: Blizzard_SharedXML, Blizzard_SharedXMLGame`
- `Blizzard_SharedXML_TBC.toc:139` loads `SharedTooltipTemplates.lua`.

**Effective body — CONFIRMS the workshop.md claim, with exact offsets**
(`Interface/AddOns/Blizzard_GameTooltip/Classic/GameTooltip.lua:109-113`):

```lua
function GameTooltip_SetDefaultAnchor(tooltip, parent)
	tooltip:SetOwner(parent, "ANCHOR_NONE");
	tooltip:SetPoint("BOTTOMRIGHT", "UIParent", "BOTTOMRIGHT", -CONTAINER_OFFSET_X - 13, CONTAINER_OFFSET_Y);
	tooltip.default = 1;
end
```

With `CONTAINER_OFFSET_Y = 70` / `CONTAINER_OFFSET_X = -4`
(`Interface/AddOns/Blizzard_UIPanels_Game/Classic/ContainerFrame_Shared.lua:14-15`),
the concrete anchor is `BOTTOMRIGHT` UIParent `BOTTOMRIGHT` at **x = -(-4)-13 = -9, y = +70**.

The shadowed shared definition (`SharedTooltipTemplates.lua:87-114`) does `SetOwner(parent, "ANCHOR_NONE")`,
then reads `GameTooltipDefaultContainer:GetPoint(1)` if that frame exists, else `SharedTooltipDefaultContainer:GetPoint(1)`,
snaps the point to the nearest corner, and `SetPoint(point, GameTooltipDefaultContainer or SharedTooltipDefaultContainer)`.
It never sets `tooltip.default`. **`GameTooltipDefaultContainer` does not exist on any classic branch**
(no `name="GameTooltipDefaultContainer"` in any .xml on anniversary/era/titan);
`SharedTooltipDefaultContainer` exists (`SharedTooltipTemplates.xml:81-86`, anchored `BOTTOMRIGHT x=-9 y=85`),
but this function is not the one running on the classic family.

### (b) What fires the default anchor, and how often — "re-driven on a timer" CONFIRMED

`GameTooltip_OnUpdate` (`Blizzard_GameTooltip/Classic/GameTooltip.lua:441-466`):

```lua
function GameTooltip_OnUpdate(self, elapsed)
	if self.recalculatePadding then
		self.recalculatePadding = nil;
		GameTooltip_CalculatePadding(self);
	end

	-- Only update every TOOLTIP_UPDATE_TIME seconds
	self.updateTooltip = (self.updateTooltip or TOOLTIP_UPDATE_TIME) - elapsed;
	if ( self.updateTooltip > 0 ) then
		return;
	end
	self.updateTooltip = TOOLTIP_UPDATE_TIME;

	local shoppingTooltip1 = self.shoppingTooltips[1];

	if ( not shoppingTooltip1:IsShown() ) then
		self.needsReset = true;
	end

	local owner = self:GetOwner();
	if ( owner and owner.UpdateTooltip ) then
		owner:UpdateTooltip();
	elseif self.UpdateTooltip then
		self:UpdateTooltip();
	end
end
```

It is wired on the GameTooltip frame itself
(`Blizzard_GameTooltip/Classic/GameTooltip.xml:33`): `<OnUpdate function="GameTooltip_OnUpdate"/>`.
`TOOLTIP_UPDATE_TIME = 0.2` (`Blizzard_UIParent/Vanilla/UIParent.lua:1`, same on TBC/Cata/Mists/Wrath variants).

The unit-frame side (`Blizzard_UnitFrame/Classic/UnitFrame.lua`):

```lua
function UnitFrame_OnEnter (self)                 -- :426
	-- If showing newbie tips then only show the explanation
	if ( GetCVar("showNewbieTips") == "1" ) then
		if ( self == PlayerFrame ) then
			GameTooltip_SetDefaultAnchor(GameTooltip, self);
			GameTooltip_AddNewbieTip(self, PARTY_OPTIONS_LABEL, 1.0, 1.0, 1.0, NEWBIE_TOOLTIP_PARTYOPTIONS);
			return;
		elseif ( self == TargetFrame and UnitPlayerControlled("target") and not UnitIsUnit("target", "player") and not UnitIsUnit("target", "pet") ) then
			GameTooltip_SetDefaultAnchor(GameTooltip, self);
			GameTooltip_AddNewbieTip(self, PLAYER_OPTIONS_LABEL, 1.0, 1.0, 1.0, NEWBIE_TOOLTIP_PLAYEROPTIONS);
			return;
		end
	end
	UnitFrame_UpdateTooltip(self);                 -- :439
end

function UnitFrame_OnLeave (self)                 -- :442
	self.UpdateTooltip = nil;
	if ( GetCVar("showNewbieTips") == "1" ) then
		GameTooltip:Hide();
	else
		GameTooltip:FadeOut();
	end
end

function UnitFrame_UpdateTooltip (self)           -- :451
	GameTooltip_SetDefaultAnchor(GameTooltip, self);
	if ( GameTooltip:SetUnit(self.unit, self.hideStatusOnTooltip) ) then
		self.UpdateTooltip = UnitFrame_UpdateTooltip;
	else
		self.UpdateTooltip = nil;
	end

	local r, g, b = GameTooltip_UnitColor(self.unit);
	GameTooltipTextLeft1:SetTextColor(r, g, b);
end
```

So the chain is: OnEnter → `UnitFrame_UpdateTooltip` → `SetDefaultAnchor` (owner + corner anchor + `default=1`)
+ `SetUnit`; while the tooltip stays shown, `GameTooltip_OnUpdate` re-invokes `owner:UpdateTooltip()`
(the same `UnitFrame_UpdateTooltip`) **every ≤0.2 s** — re-applying `GameTooltip_SetDefaultAnchor`
(SetOwner + SetPoint to the default corner + `default=1`) on every tick, as long as
`SetUnit` keeps succeeding (the frame's `UpdateTooltip` field is only nil'd on OnLeave or SetUnit failure).

Other unit-tooltip drivers on this branch, same contract:

- Party frames: `PartyMemberFrameMixin:OnEnter` (`Blizzard_UnitFrame/Classic/PartyMemberFrame.lua:406-410`) → `UnitFrame_OnEnter(self)`.
- Raid buttons: `UnitFrame_UpdateTooltip(raidbutton)` (`Blizzard_RaidUI/Blizzard_RaidUI.lua:655`; XML OnEnter handlers at `Blizzard_RaidUI.xml:488,511,622`).

### (c) SetOwner / OnHide / OnTooltipCleared behavior

`SetOwner` is a **native (C++) method** on the classic family — grepping anniversary for
`function ...:SetOwner` finds only non-GameTooltip helpers (GlueTooltip, CooldownViewer);
there is **no Lua body to quote** for GameTooltip:SetOwner on any of the five branches.
Its effect on existing anchors cannot be proven from the UI mirror alone. Observable contract from FrameXML:

- `GameTooltip_SetDefaultAnchor` does `SetOwner` then `SetPoint` **without** `ClearAllPoints`, and is re-applied every 0.2 s while shown — stable in Blizzard's own UI, so either `SetOwner(ANCHOR_NONE)` resets anchors natively, or repeated identical SetPoint (same point + same relativeTo + relativePoint) replaces the one anchor in place (standard FrameXML SetPoint semantics: replace-on-same-triple, add-on-different-triple).
- By contrast `GameTooltip_SetBasicTooltip` (`Classic/GameTooltip.lua:115-121`) does the explicit dance:
  `SetOwner(UIParent, "ANCHOR_NONE"); self:ClearAllPoints(); self:SetPoint("BOTTOMLEFT", ...)` —
  i.e. the manual-position pattern in the same file clears points itself.

`GameTooltip_OnHide` (`Classic/GameTooltip.lua:413-430`):

```lua
function GameTooltip_OnHide(self)
	self.needsReset = true;
	local style = nil;
	SharedTooltip_SetBackdropStyle(self, style, self.IsEmbedded);
	self.default = nil;
	...
```

OnHide clears `default` but **does not ClearOwner and does not ClearAllPoints** (no `ClearOwner`
call anywhere in Blizzard_GameTooltip/Blizzard_SharedXML on this branch). The owner and any anchor
points survive the hide. `OnTooltipCleared` (`GameTooltipTemplate.lua:20-23`, mixin method)
only clears money + inserted frames — no position effect.

### (d) Classic GameTooltip XML — no OnShow on the frame. CONFIRMED

`Blizzard_GameTooltip/Classic/GameTooltip.xml` — the `GameTooltip` frame (lines 16-35):

```xml
<GameTooltip name="GameTooltip" frameStrata="TOOLTIP" hidden="true" parent="UIParent" inherits="GameTooltipTemplate">
	<Scripts>
		<OnLoad> ... GameTooltip_OnLoad(self); self.shoppingTooltips = { ShoppingTooltip1, ShoppingTooltip2 }; ... </OnLoad>
		<OnTooltipSetUnit function="GameTooltip_OnTooltipSetUnit" />
		<OnTooltipSetItem function="GameTooltip_OnTooltipSetItem" />
		<OnTooltipSetSpell function="GameTooltip_OnTooltipSetSpell" />
		<OnHide>
			GameTooltip_OnHide(self);
			ShoppingTooltip1:Hide();
			ShoppingTooltip2:Hide();
			...
		</OnHide>
		<OnUpdate function="GameTooltip_OnUpdate"/>
	</Scripts>
</GameTooltip>
```

**No OnShow** on the GameTooltip frame. The template (`SharedXML/Classic/GameTooltipTemplate.xml:22`,
`GameTooltipTemplate ... mixin="GameTooltipMixin"`, `clampedToScreen="true"`) adds
OnLoad / OnHide / OnTooltipSetDefaultAnchor / OnTooltipAddMoney / OnTooltipCleared —
also **no OnShow**. The only OnShow in the file belongs to `SmallTextTooltip`, an unrelated frame.
Nothing in the classic GameTooltip path re-anchors on show. `GameTooltipMixin:OnTooltipSetDefaultAnchor`
(`SharedXML/Classic/GameTooltipTemplate.lua:12-14`) exists but only fires if the
`OnTooltipSetDefaultAnchor` callback is raised by the client — it is not an OnShow hook.

### (e) What can explain "stuck mid-screen on second hover, resets after some time"

- **`default` is written, never read by Blizzard code.** `tooltip.default = 1` (Classic/GameTooltip.lua:112),
  `self.default = nil` (OnHide, :417). A branch-wide grep finds no other `.default` reader/writer
  in Blizzard_GameTooltip, Blizzard_SharedXML, Blizzard_FrameXML, Blizzard_UIParent on anniversary.
  It is a flag aimed at addons (vanilla-2004 heritage; e.g. TacoTip can check `GameTooltip.default`
  to know the client considers the tooltip "at its default spot"). The same pattern even survives on
  retail: `FrameStackTooltip_Show` (`live:Blizzard_DebugTools/Blizzard_DebugTools.lua:133-141`)
  does the identical `SetOwner(ANCHOR_NONE) + SetPoint(BOTTOMRIGHT, UIParent, ...) + self.default = 1`.
- **The 0.2 s re-drive stomps addon positions while the mouse rests on a unit frame.** Any
  reposition applied once (e.g. in OnShow or on the first OnTooltipSetUnit) is overwritten by the
  next `owner:UpdateTooltip()` tick unless the addon re-applies after every `SetDefaultAnchor`
  (e.g. every OnTooltipSetUnit, which fires from `SetUnit` inside `UnitFrame_UpdateTooltip`).
- **Multi-anchor smear.** If the addon positions with a different point name (e.g. `CENTER`) and
  never removes it, the client's `SetPoint("BOTTOMRIGHT", UIParent, ...)` does not replace it —
  the tooltip carries two anchors and is laid out to satisfy both (mid-screen stretch/stuck look)
  until one point is removed.
- **Stale owner across hide is harmless by itself.** OnHide doesn't ClearOwner, but OnUpdate only
  runs on a shown frame, so a hidden tooltip cannot self-move. On re-hover, OnEnter re-owns.
- **The only client-side "frozen until reset" window:** if the tooltip is shown while the owner has
  no `UpdateTooltip` (SetUnit failed → `self.UpdateTooltip = nil`, or owner is a plain frame),
  the 0.2 s re-drive does nothing — the tooltip stays wherever it was last pointed until some
  later OnEnter → `UnitFrame_UpdateTooltip` → `SetDefaultAnchor` re-stamps the corner.
  That is the only client mechanism matching "stuck, then resets by itself some time later".

---

## classic_era — every claim above carries over verbatim

`git diff --ignore-cr-at-eol classic_anniversary classic_era` is empty (0 lines) for:
`Blizzard_GameTooltip/Classic/GameTooltip.lua`, `Blizzard_GameTooltip/Classic/GameTooltip.xml`,
`Blizzard_UnitFrame/Classic/UnitFrame.lua`, `Blizzard_UnitFrame/Classic/PartyMemberFrame.lua`,
`Blizzard_SharedXML/Classic/GameTooltipTemplate.xml`, `Blizzard_SharedXML/Classic/GameTooltipTemplate.lua`,
`Blizzard_SharedXML/SharedTooltipTemplates.lua`, `Blizzard_RaidUI/Blizzard_RaidUI.lua`,
`Blizzard_RaidUI/Blizzard_RaidUI.xml`, `Blizzard_UIPanels_Game/Classic/ContainerFrame_Shared.lua`
(raw diff shows only whole-file CRLF replacement; same blob line numbers, same functions at :109/:441/:451).
`TOOLTIP_UPDATE_TIME = 0.2` (`Blizzard_UIParent/Vanilla/UIParent.lua:1`).
`CONTAINER_OFFSET_Y=70`, `CONTAINER_OFFSET_X=-4` (`ContainerFrame_Shared.lua:14-15`).
Dep chain identical (`Blizzard_GameTooltip_Classic.toc` → Blizzard_UIParent →
`Blizzard_FrameXMLBase_Vanilla.toc` → Blizzard_SharedXML). **The workshop.md byte-identical claim
for era/anniversary is CONFIRMED.**

---

## classic_titan — identical to anniversary as well

`git diff --ignore-cr-at-eol` empty for the same 8 files (GameTooltip.lua/xml, UnitFrame.lua,
PartyMemberFrame.lua, GameTooltipTemplate.xml/lua, SharedTooltipTemplates.lua, RaidUI.lua).
Same function line numbers (:109 SetDefaultAnchor, :441 OnUpdate, :451 UnitFrame_UpdateTooltip).
`TOOLTIP_UPDATE_TIME = 0.2` in all Blizzard_UIParent game-type variants.
Blizzard_GameTooltip_Classic.toc blob is literally the same hash as anniversary (27e49bcc…).
Same conclusion set (a)-(e) as anniversary.

---

## forever (`remotes/origin/forever`) — DIFFERENT SHAPE (Mainline layout)

Local branch `forever` does not exist; `git show forever:...` fails. Everything below is
`git show remotes/origin/forever:...`.

- **(a)** Only ONE definition: the shared `GameTooltip_SetDefaultAnchor`
  (`Blizzard_SharedXML/SharedTooltipTemplates.lua:87-114`) — `SetOwner(parent, "ANCHOR_NONE")`,
  then anchors to `GameTooltipDefaultContainer` if present (it IS present here:
  `Blizzard_GameTooltip/Mainline/GameTooltip.xml:242-247`, anchored `BOTTOMRIGHT x=-9 y=85` to UIParent),
  else `SharedTooltipDefaultContainer`. No Classic UIParent-corner override, **no `tooltip.default = 1`**.
- **(b)** Re-drive exists in the same shape: `GameTooltip_OnUpdate`
  (`Blizzard_GameTooltip/Mainline/GameTooltip.lua:460-473`) gates on
  `GameTooltip_IsUpdateNeeded` (`updateTooltipTimer`, `TOOLTIP_UPDATE_TIME = 0.2` from
  `Blizzard_SharedXML/SharedConstants.lua:145`), then `owner:UpdateTooltip()` /
  `self:UpdateTooltip()` / `self:RefreshData()`. `UnitFrame_UpdateTooltip`
  (`Blizzard_UnitFrame/Mainline/UnitFrame.lua:396-408`) = `SetDefaultAnchor` + `SetUnit` +
  `Show()` + `self.UpdateTooltip = UnitFrame_UpdateTooltip`; `UnitFrame_OnEnter` (:387) calls it.
- **(c)** `SetOwner` native, no Lua body (same grep result).
- **(d)** DIFFERENT from classic: the `GameTooltip` frame HAS an OnShow
  (`Mainline/GameTooltip.xml:271` → `GameTooltip_OnShow`, `Mainline/GameTooltip.lua:380-402`),
  but it does **not** re-anchor: `NarratableTooltipMixin.OnShow` (event registry only,
  `SharedTooltipTemplates.lua:274`), an edit-mode HUD-tooltip hide check, and
  `GameTooltip_CalculatePadding`. `GameTooltip_OnHide` (:404-430) clears data/handlers
  (`self:ClearHandlerInfo()`), no ClearOwner, no point clear.
- **(e)** No `.default` flag written by SetDefaultAnchor on this family; the 0.2 s re-drive
  mechanics are otherwise the same.

---

## live (`origin/live`) — same Mainline shape as forever; anchor machinery identical

Diff forever↔live does not touch anchor logic:
`SharedTooltipTemplates.lua` loses only `GameTooltip_AddLineWithInputIcon`;
`GameTooltip.lua` loses only a gamepad block inside OnShow (+whitespace);
`UnitFrame.lua` diffs are name-handling only (UnitFrame_UpdateTooltip untouched);
`GameTooltip.xml` loses only the `BuffFrameTooltip` frame.
`GameTooltip_OnShow` on live (`Mainline/GameTooltip.lua:380-393`): Narratable event +
edit-mode hide check + `GameTooltip_CalculatePadding` — no re-anchor.
`GameTooltip_SetDefaultAnchor` on live = the shared body quoted above (identical 87-114).
`GameTooltipDefaultContainer` exists (`Mainline/GameTooltip.xml:242`), `BOTTOMRIGHT -9 85`.

---

## WHAT THIS MEANS FOR A RE-HOVER

### Client-side lifecycle on the operator's branches (classic_anniversary / classic_era — identical)

1. **Hide** (OnLeave → `UnitFrame_OnLeave`): `self.UpdateTooltip = nil` on the frame;
   `GameTooltip:Hide()` or `:FadeOut()`. `GameTooltip_OnHide` sets `needsReset`, clears
   `default`, hides shopping tooltips. **Owner and anchor points are not cleared in Lua.**
2. **Re-enter** (OnEnter → `UnitFrame_OnEnter` → `UnitFrame_UpdateTooltip`): fresh
   `GameTooltip_SetDefaultAnchor` — `SetOwner(frame, "ANCHOR_NONE")` + `SetPoint("BOTTOMRIGHT",
   UIParent, "BOTTOMRIGHT", -9, 70)` + `default = 1` — then `SetUnit`, then the frame's
   `UpdateTooltip` is re-armed. There is no first-vs-second-hover distinction anywhere in the
   client code: **first hover and re-hover execute the same lines.** The only difference is
   leftover state (owner, anchors, addon-saved variables) from the previous cycle.
3. **Steady state while shown**: every ≤0.2 s, `GameTooltip_OnUpdate` → `owner:UpdateTooltip()`
   → `GameTooltip_SetDefaultAnchor` again. The default corner anchor is re-stamped continuously.

### Which client calls can move a tooltip an addon has already positioned (classic family)

| Call | When | Effect on an addon-set position |
| :--- | :--- | :--- |
| `GameTooltip_SetDefaultAnchor` (via OnEnter and via 0.2 s OnUpdate re-drive) | every hover + every ≤0.2 s while shown with a unit-frame owner | `SetOwner(ANCHOR_NONE)` + `SetPoint(BOTTOMRIGHT, UIParent, …, -9, 70)`: replaces a same-triple BOTTOMRIGHT anchor (tooltip jumps back to corner); coexists as a second anchor with a differently-named point (e.g. addon `CENTER`) → multi-anchor layout, tooltip stuck/stretched mid-screen until one point is removed |
| `SetUnit` (inside `UnitFrame_UpdateTooltip`, both OnEnter and re-drive) | every re-drive tick | fires `OnTooltipSetUnit` — an addon hooking this repositions AFTER the client's SetDefaultAnchor in the same call, which is the only hook that wins the 0.2 s race reliably |
| `GameTooltip_OnShow` | n/a on classic | **does not exist** on the classic GameTooltip frame/template — nothing re-anchors on show |
| `GameTooltip_OnHide` | on hide | clears `default` and content state only; position/owner survive — a tooltip re-shown without going through `SetDefaultAnchor` keeps the last points |

Two facts that explain the operator's exact symptom shape:

- **"First hover OK":** OnEnter's `SetDefaultAnchor` + the addon's save/restore can coexist on the
  first pass if the restore runs after SetDefaultAnchor in the same frame (OnTooltipSetUnit or OnShow-equivalent hook).
- **"Re-hover stuck, resets later":** the re-hover path is code-identical to first hover, so any
  stuck state must come from stale anchor points/owner left by the previous cycle plus the 0.2 s
  re-drive either (i) stomping the restore back to the corner every tick, or (ii) NOT running
  (owner without `UpdateTooltip`, or `UpdateTooltip` nil'd by a SetUnit failure), leaving the
  addon's last mid-screen anchor frozen until some later OnEnter re-drives `SetDefaultAnchor`.
  The client provides no "restore position" call of its own — only the default-corner stamp.

### Claims status vs workshop.md

- SetDefaultAnchor body (ANCHOR_NONE → UIParent BOTTOMRIGHT (-CONTAINER_OFFSET_X-13, CONTAINER_OFFSET_Y) → default=1): **CONFIRMED on classic_anniversary and classic_era** (byte-identical modulo CRLF), same on classic_titan; **CORRECTED for forever/live** — there the shared container-anchored version runs and no `default` flag is set.
- "Re-driven on a timer": **CONFIRMED** on all five branches (0.2 s OnUpdate → owner:UpdateTooltip).
- "No OnShow on the classic GameTooltip": **CONFIRMED** on anniversary/era/titan; forever/live DO have OnShow but it does not re-anchor.
- SetOwner anchor-reset semantics: **unprovable from the mirror** (native method on all five branches) — stated as observable contract only, flagged above.
