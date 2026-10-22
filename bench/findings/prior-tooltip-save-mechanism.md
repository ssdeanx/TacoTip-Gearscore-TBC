# Prior Working Version — FULL TRACE: save → re-save → re-apply loop, cache-spined

**Source tree:** `/home/sam/TacoTip/` (read-only; NOT the repo under test)
**Version:** `0.8.3` — `TacoTip.toc:2` `## Version: 0.8.3`
**Clients:** one multi-interface TOC — `TacoTip.toc:1`
`## Interface: 11509, 20506, 38002, 16001, 120105` (era, **TBC Anniversary 20506**,
titanforge, forever, retail) — covers the operator's `classic_anniversary`.
`TacoTip.toc:8` `## SavedVariables: TacoTipConfig`.
**Investigation:** 2026-10-22, desk `prior-tooltip-save`. Read-only; no code edited
in either tree. Scope amendment (operator): full data-flow trace across the whole
tree, cache lifecycle as the spine.

---

## 0. Files involved and load order

From `TacoTip.toc` (numbered):

```
11: Libs\LibStub\LibStub.lua
12: Libs\CallbackHandler-1.0\CallbackHandler-1.0.lua
13: Libs\LibDetours-1.0\LibDetours-1.0.lua
14: Libs\LibForeverInspector\LibForeverInspector.lua
16-26: Locale\*.lua  (11 locales)
28: gearscore.lua
29: pawn.lua
30: textures.lua
31: options.lua
32: main.lua
```

- **`gearscore.lua`** loads first of the addon files: registers the *bootstrap*
  slash handler (replaced later by options.lua) and the item-load completion
  callbacks that fire `TacoTip_GSCallback`.
- **`options.lua`** loads before `main.lua`: owns the positioning UI and the
  *final* slash handler; every reference to `TacoTip_CustomPosEnable` /
  `TacoTipDragButton` here is runtime-guarded because those are defined later
  (`options.lua:348` `if (TacoTip_CustomPosEnable)`, `options.lua:2499`).
- **`main.lua`** loads last: owns the cache, the anchor hook, and the drag
  handle. `TacoTip_CustomPosEnable` is defined near the end at `main.lua:3695`.
- **LibDetours-1.0** (`Libs/LibDetours-1.0/LibDetours-1.0.lua`) is used in
  `main.lua` for exactly two things: the instant-fade `FadeOut` detour
  (`main.lua:3596`) and the mover-mode GameTooltip `OnShow`/`OnHide` hooks
  (`main.lua:3789`–`3803`). The `GameTooltip_SetDefaultAnchor` post-hook is a
  **plain `hooksecurefunc`**, not a Detours hook.
- Files that write position state: `main.lua`, `options.lua`, `gearscore.lua`.
  `pawn.lua`, `textures.lua`, `Locale/*`, `Libs/*` do not touch position or the
  unit cache (grep `custom_pos|SetDefaultAnchor|GameTooltip:SetPoint` → only the
  three files above).

---

## 1. THE CACHE (the spine)

### 1.1 Definition — `main.lua:165`–`198`

Stored **on the tooltip frame itself**, not in a module table:

```lua
main.lua:165: -- Per-tooltip lifecycle state, stored on the frame as tooltip._tacoTipState.
main.lua:166: -- All handles are cleared or invalidated by clearTooltipVisuals on every
main.lua:167: -- clear/hide transition.
main.lua:168: ---@class tacoTipTooltipState
main.lua:169: ---@field generation integer           -- clear/hide epoch; stale callbacks bail on mismatch
main.lua:170: ---@field currentUnitGUID string|nil   -- GUID of the unit currently rendered
main.lua:171: ---@field currentItemLink string|nil   -- item link currently rendered
main.lua:172: ---@field itemLoadCancel function|nil  -- ItemMixin:ContinueWithCancelOnItemLoad canceler
main.lua:173: ---@field delayedTooltipTimer table|nil -- cancellable NewTimer handle (unit-tooltip delay)
main.lua:174: ---@field borderDeferTimer table|nil    -- cancellable NewTimer handle (defensive border re-apply)
main.lua:175: ---@field classBorderDeferTimer table|nil -- cancellable NewTimer handle (OnShow class-border re-apply)
main.lua:176: ---@field fadeTimer table|nil           -- cancellable NewTimer handle (instant fade)
```

```lua
main.lua:190: local function getTooltipState(tooltip)
main.lua:191:     if (not tooltip) then
main.lua:192:         return nilTooltipState
main.lua:193:     end
main.lua:194:     if (not tooltip._tacoTipState) then
main.lua:195:         tooltip._tacoTipState = { generation = 0 }
main.lua:196:     end
main.lua:197:     return tooltip._tacoTipState
main.lua:198: end
```

(Plus session-late fields written without doc lines: `inspectRenderGUID` /
`inspectRenderTime` at `main.lua:3664-3665`, `portraitSide` / `portraitAnchored`
at `main.lua:1368-1369` / `1153-1155`.)

### 1.2 Where the unit is WRITTEN into the cache

Single write site for the unit GUID — `main.lua:1618`–`1631` (inside
`onTooltipSetUnit`, defined `main.lua:1532`):

```lua
main.lua:1618:     local guid = (data and data.guid) or UnitGUID(tooltipUnit)
...
main.lua:1622:     local previousGUID = getTooltipState(tooltip).currentUnitGUID
...
main.lua:1629:     clearTooltipVisuals(tooltip, nil, (previousGUID ~= nil and previousGUID == guid), "guid-change")
main.lua:1630:     getTooltipState(tooltip).currentUnitGUID = guid
main.lua:1631:     storeTooltipPlayerClassColor(tooltip, tooltipUnit)
```

The unit is resolved first (`main.lua:1545` `tooltipUnit = resolveTooltipUnit(tooltip, tooltipUnit)`;
`resolveTooltipUnit` defined at `main.lua:981`, walks explicit unit →
`TooltipUtil.GetDisplayedUnit` → `GetUnit` → owner's `.unit` → mouseover
only if really mouseover).

### 1.3 Where the cached unit is READ (every consumer)

| # | Site | What it decides |
|---|---|---|
| R1 | `main.lua:1622` | `previousGUID` vs new guid → `keepModel` for `clearTooltipVisuals` (portrait teardown vs no-op) |
| R2 | `main.lua:1595-1598` | unresolved-unit branch: `incomingGUID == unresolvedState.currentUnitGUID` → "change unproven" → skip teardown, **`return` before render** |
| R3 | `main.lua:2696-2716` | `isUnitFramePeriodicUpdate`: owner has `.UpdateTooltip`, owner `.unit` exists, and `UnitGUID(owner.unit) == state.currentUnitGUID` |
| R4 | R3's callers `main.lua:2724` (OnTooltipCleared) and `main.lua:2738` (OnHide) | **suppress `clearTooltipVisuals`** during a steady same-unit hover |
| R5 | `main.lua:1633-1644` | mover mode: `TacoTipDragButton:IsShown()` + `UnitIsUnit(tooltipUnit, "player")` → non-player units get `ShowExample()` + early `return` |
| R6 | `main.lua:1267-1271` (GSCallback) | live `resolveTooltipUnit` + `UnitGUID(ttUnit) == guid` else skip re-render (`TT.ev.gsCallbackWrongUnit`) |
| R7 | `main.lua:3649-3650` (INVENTORY_READY/TALENTS_READY) | live `resolveTooltipUnit` + `UnitGUID(ttUnit) == guid` gate before re-`SetUnit` |

```lua
main.lua:2696: local function isUnitFramePeriodicUpdate(tooltip)
...
main.lua:2704:     local state = getTooltipState(tooltip)
main.lua:2705:     local curGUID = state and state.currentUnitGUID
main.lua:2706:     if (not curGUID) then
main.lua:2707:         return false
main.lua:2708:     end
main.lua:2709:     if (owner.UpdateTooltip and owner.unit and UnitExists and UnitExists(owner.unit)) then
main.lua:2710:         local uGUID = UnitGUID(owner.unit)
main.lua:2711:         if (uGUID and uGUID == curGUID) then
main.lua:2712:             return true
main.lua:2713:         end
main.lua:2714:     end
main.lua:2715:     return false
main.lua:2716: end
```

**None of R1–R7 reads or writes `TacoTipConfig.custom_pos`, and none of them
SetPoint the GameTooltip** — with one conditional exception: R5 (mover mode,
handle visible) re-anchors through `ShowExample`. This is the structural answer
to the operator's hypothesis; §4 spells it out.

### 1.4 What CLEARS the cache

`clearTooltipVisuals` — `main.lua:1327`–`1340`:

```lua
main.lua:1327: local function clearTooltipVisuals(tooltip, preservePendingItem, keepModel, reason, retainModel)
...
main.lua:1331:     local state = getTooltipState(tooltip)
main.lua:1332:     if (not preservePendingItem) then
main.lua:1333:         state.generation = state.generation + 1
main.lua:1334:         cancelItemLoadRefresh(tooltip)
main.lua:1335:         state.currentItemLink = nil
main.lua:1336:     end
main.lua:1338:     cancelDelayedTooltip(tooltip)
main.lua:1339:     cancelDeferredAppearance(tooltip)
main.lua:1340:     cancelFadeTimer(tooltip)
```

Callers (reason strings): `"guid-change"` (`main.lua:1629`),
`"unresolved-unit"` (`main.lua:1614`), `"show-no-class-cache"` (`main.lua:2646`),
`"cleared"` (OnTooltipCleared, `main.lua:2728`), `"hide"` (OnHide, `main.lua:2744`).

**`currentUnitGUID` is never niled.** The addon documents this itself —
`main.lua:3368`–`3374`:

```lua
main.lua:3368:     -- The old text here read "portrait destroy should be ~1 for a character and
main.lua:3369:     -- 0 for a re-hover of the same one". That is only true for the FIRST unit
main.lua:3370:     -- rendered after a /reload: state.currentUnitGUID is assigned at :1586 and
main.lua:3371:     -- is NEVER cleared, so it always holds the unit rendered most recently --
```
(the comment's `:1586` is stale numbering; the write is at `main.lua:1630`.)

And OnHide/OnTooltipCleared don't even run when the periodic-update gate says
"same unit, still hovering" — `main.lua:2722`–`2746`:

```lua
main.lua:2722:     if (tooltipFrame:HasScript("OnTooltipCleared")) then
main.lua:2723:         tooltipFrame:HookScript("OnTooltipCleared", function(tFrame)
main.lua:2724:             if (isUnitFramePeriodicUpdate(tFrame)) then
main.lua:2725:                 return
main.lua:2726:             end
main.lua:2727:             cancelDelayedTooltip(tFrame)
main.lua:2728:             return safeCall(clearTooltipVisuals, tFrame, nil, nil, "cleared", true)
main.lua:2729:         end)
main.lua:2730:     end
main.lua:2731:     if (tooltipFrame:HasScript("OnShow")) then
main.lua:2732:         tooltipFrame:HookScript("OnShow", function(tFrame, ...)
main.lua:2733:             return safeCall(onTooltipShow, tFrame, ...)
main.lua:2734:         end)
main.lua:2735:     end
main.lua:2736:     if (tooltipFrame:HasScript("OnHide")) then
main.lua:2737:         tooltipFrame:HookScript("OnHide", function(tFrame)
main.lua:2738:             if (isUnitFramePeriodicUpdate(tFrame)) then
main.lua:2739:                 return
main.lua:2740:             end
main.lua:2741:             cancelDelayedTooltip(tFrame)
main.lua:2742:             -- Same reasoning as OnTooltipCleared: a hide is not proof the
main.lua:2743:             -- character changed, and the model is already hidden.
main.lua:2744:             return safeCall(clearTooltipVisuals, tFrame, nil, nil, "hide", true)
main.lua:2745:         end)
main.lua:2746:     end
```

Registered by `registerTooltipVisualClearing` (`main.lua:2718`), applied to
GameTooltip and the other tooltip frames (list at `main.lua:2749+`).

**The position state (`TacoTipConfig.custom_pos`) lives in the SavedVariable,
not in this cache.** Nothing in §1 clears or writes it.

---

## 2. FIRST-HOVER TRACE (feature ON: `custom_pos` set, handle hidden after save)

Setup: `TacoTipConfig.custom_pos = {"BOTTOMLEFT","BOTTOMLEFT",x,y}` from a prior
save; `TacoTipDragButton` exists (created at `ADDON_LOADED`, `main.lua:3588-3590`)
and is hidden (`_Save` hid it, `main.lua:3891`).

**Hop 1 — mouse enters a unit frame** (client, `origin/classic_anniversary`):
`UnitFrame_OnEnter` → `UnitFrame_UpdateTooltip`
(`Interface/AddOns/Blizzard_UnitFrame/Classic/UnitFrame.lua:449-457`):

```lua
function UnitFrame_UpdateTooltip (self)
	GameTooltip_SetDefaultAnchor(GameTooltip, self);
	if ( GameTooltip:SetUnit(self.unit, self.hideStatusOnTooltip) ) then
		self.UpdateTooltip = UnitFrame_UpdateTooltip;
```

**Hop 2 — the original `GameTooltip_SetDefaultAnchor` runs** (client,
`origin/classic_anniversary:Interface/AddOns/Blizzard_GameTooltip/Classic/GameTooltip.lua:109-114`):

```lua
function GameTooltip_SetDefaultAnchor(tooltip, parent)
	tooltip:SetOwner(parent, "ANCHOR_NONE");
	tooltip:SetPoint("BOTTOMRIGHT", "UIParent", "BOTTOMRIGHT", -CONTAINER_OFFSET_X - 13, CONTAINER_OFFSET_Y);
	tooltip.default = 1;
end
```

→ tooltip is parked at the **bottom-right corner** and `SetOwner` clears the
lines (OnTooltipCleared fires → addon's handler at `main.lua:2723`, which for a
still-hovering same unit **returns early via R4** — cache survives; on a genuine
first hover `currentUnitGUID` is nil → gate false → `clearTooltipVisuals`
runs and bumps `generation`).

**Hop 3 — the addon post-hook re-pins to the handle** — registered
`main.lua:2862`–`2864`:

```lua
main.lua:2862: if (type(_G.GameTooltip_SetDefaultAnchor) == "function") then
main.lua:2863:     hooksecurefunc("GameTooltip_SetDefaultAnchor", onGameTooltipSetDefaultAnchor)
main.lua:2864:     TT.HookedDefaultAnchor = true
```

body `main.lua:2811`–`2852`, decision chain verbatim:

```lua
main.lua:2811: local function onGameTooltipSetDefaultAnchor(tooltip, parent)
main.lua:2812:     if (TacoTipConfig.anchor_mouse_spells) then
...
main.lua:2814:         if (parent and (parent.action or parent.spellId or (parentparent and parentparent.action) or (parentparent and parentparent.spellId))) then
...
main.lua:2823:             return
main.lua:2824:         end
main.lua:2825:     end
main.lua:2826:     if (TacoTipConfig.anchor_mouse) then
main.lua:2827:         if (not TacoTipConfig.anchor_mouse_world or TT:GetMouseFocus() == WorldFrame) then
...
main.lua:2831:             tooltip:ClearAllPoints()
main.lua:2832:             tooltip:SetPoint("BOTTOMLEFT", TacoTipMouseAnchor, "CENTER", 10, 10)
main.lua:2833:         end
main.lua:2834:     else
main.lua:2835:         if (TacoTipConfig.custom_pos) then
main.lua:2836:             if (not TacoTipDragButton and TacoTip_CustomPosEnable) then
main.lua:2837:                 TacoTip_CustomPosEnable(false)
main.lua:2838:             end
main.lua:2839:             if (TacoTipDragButton) then
main.lua:2840:                 tooltip:ClearAllPoints()
main.lua:2841:                 local anchorPoint = TacoTipConfig.custom_anchor or "TOPLEFT"
main.lua:2842:                 tooltip:SetPoint(anchorPoint, TacoTipDragButton, anchorPoint)
main.lua:2843:             end
main.lua:2844:         elseif (TacoTipConfig.show_hp_bar and TacoTipConfig.show_power_bar) then
main.lua:2845:             tooltip:ClearAllPoints()
main.lua:2846:             tooltip:SetPoint("BOTTOMRIGHT", "UIParent", "BOTTOMRIGHT", -CONTAINER_OFFSET_X - 13, CONTAINER_OFFSET_Y + 9)
main.lua:2847:         end
main.lua:2848:     end
main.lua:2849:     if (tooltip.EnableMouse) then
main.lua:2850:         tooltip:EnableMouse(false)
main.lua:2851:     end
main.lua:2852: end
```

**No unit argument exists in this function signature beyond Blizzard's
`(tooltip, parent)`; no unit/GUID/state lookup happens anywhere between entry
and the `SetPoint` at 2842.** The bottom-right corner from Hop 2 is overwritten
in the same call.

**Hop 4 — `SetUnit` writes content** (Hop 1 continues): client fires the
`OnTooltipSetUnit` script (declared by the Classic template,
`origin/classic_anniversary:Interface/AddOns/Blizzard_SharedXML/Classic/GameTooltipTemplate.xml:153`
declares the sibling `OnTooltipSetDefaultAnchor`; unit script declared likewise)
→ addon registration `main.lua:2413`–`2418`:

```lua
main.lua:2413: TT.HookedTooltipScripts.Unit = TT.HookedTooltipScripts.Unit
main.lua:2414:     or hookTooltipScripts("OnTooltipSetUnit",
main.lua:2415:         function(tooltip, ...)
main.lua:2416:             handleTooltipSetUnit(tooltip)
main.lua:2417:         end,
main.lua:2418:         { { GameTooltip, "GameTooltip" } })
```
(or `TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, handleTooltipSetUnit)`
on pipeline clients, `main.lua:2410`).

**Hop 5 — optional time gate:** `handleTooltipSetUnit`, `main.lua:2347`–`2363`:

```lua
main.lua:2347: local function handleTooltipSetUnit(tooltip, data)
main.lua:2348:     cancelDelayedTooltip(tooltip)
main.lua:2349:     local delay = TacoTipConfig.tooltip_delay or 0
main.lua:2350:     if (delay > 0 and tooltip == GameTooltip and not InCombatLockdown() and type(NewTimer) == "function") then
main.lua:2351:         local state = getTooltipState(tooltip)
...
main.lua:2353:         timer = NewTimer(delay, function()
...
main.lua:2357:             safeCall(onTooltipSetUnit, tooltip, data)
main.lua:2358:         end)
main.lua:2359:         state.delayedTooltipTimer = timer
main.lua:2360:     else
main.lua:2361:         safeCall(onTooltipSetUnit, tooltip, data)
main.lua:2362:     end
main.lua:2363: end
```

Position is **already applied** at Hop 3; this delay only postpones the render.

**Hop 6 — `onTooltipSetUnit` fills the cache** (`main.lua:1532`):
resolve (`1545`) → unresolved? cache-decision R2 + `clearTooltipVisuals` +
`return` (`1595-1615`) → else: guid (`1618`), `previousGUID` (`1622`),
keepModel clear (`1629`), **`state.currentUnitGUID = guid` (`1630`)**.

**Hop 7 — mover gate (only if handle is visible):** `main.lua:1633`–`1644`:

```lua
main.lua:1633:     if (TacoTipDragButton and TacoTipDragButton:IsShown()) then
main.lua:1634:         if (not UnitIsUnit(tooltipUnit, "player")) then
...
main.lua:1638:             TT:ApplyTooltipAppearance(tooltip, tooltipUnit)
main.lua:1639:             if (TacoTipDragButton.ShowExample) then
main.lua:1640:                 TacoTipDragButton:ShowExample()
main.lua:1641:             end
main.lua:1642:             return
main.lua:1643:         end
main.lua:1644:     end
```

In normal play (handle hidden after save) this never fires. In mover mode this
is the **one place a unit decision re-anchors the tooltip** — `ShowExample`,
`main.lua:3842`–`3846`:

```lua
main.lua:3842:             if (TacoTipConfig.custom_pos) then
main.lua:3843:                 GameTooltip:SetOwner(TacoTipDragButton, "ANCHOR_NONE")
main.lua:3844:                 GameTooltip:ClearAllPoints()
main.lua:3845:                 local anchorPoint = TacoTipConfig.custom_anchor or "TOPLEFT"
main.lua:3846:                 GameTooltip:SetPoint(anchorPoint, TacoTipDragButton, anchorPoint)
```

**Hop 8 — render tail (content/layout only, no GameTooltip position change):**
inspect kick (`main.lua:1646-1650`), styles (`1652+`), power bar attached *to*
the tooltip (`main.lua:2215-2216`, offset memo `2268-2270`), then:

```lua
main.lua:2306:     if (tooltip.SetClampRectInsets) then
main.lua:2307:         if (tooltip._tacoTipClampBottom ~= 15) then
main.lua:2308:             tooltip:SetClampRectInsets(0, 0, 15, 15)
...
main.lua:2313:     if (tooltip.SetMinimumWidth) then
...
main.lua:2316:             tooltip:SetMinimumWidth(0)
...
main.lua:2321:     applyTooltipMaxWidth(tooltip)
main.lua:2322: 
main.lua:2323:     TT:ApplyTooltipAppearance(tooltip, tooltipUnit)
main.lua:2324: end
```

(`SetClampRectInsets` / `SetMinimumWidth(0)` / `applyTooltipMaxWidth` shape the
box; they do not move the anchor.)

**Hop 9 — OnShow visuals:** OnShow hook (`main.lua:2731-2735`) → `onTooltipShow`
(`main.lua:2617`) — class-border work behind `state.generation` (`2661`,
`2674`), no position code.

Net of first hover: **position applied at Hop 3 (before content), cache filled
at Hop 6, no later hop moves the tooltip.**

---

## 3. SAVE / RE-SAVE — every writer of the position state

### 3.1 The real save (drag stop) — `main.lua:3715`–`3732`

```lua
main.lua:3715:         local function onDragButtonDragStop(self)
main.lua:3716:             self:SetScript("OnUpdate", nil)
main.lua:3717:             self:StopMovingOrSizing()
main.lua:3718:             -- GetPoint() is unreliable after StopMovingOrSizing() — WoW's
main.lua:3719:             -- drag system leaves the frame's anchor state in an intermediate
main.lua:3720:             -- state where GetPoint() can return nil anchor values.  Use
main.lua:3721:             -- pixel-position getters relative to UIParent's BOTTOMLEFT origin
main.lua:3722:             -- (the WoW screen coordinate origin) instead.
main.lua:3723:             local left = self:GetLeft()
main.lua:3724:             local bottom = self:GetBottom()
main.lua:3725:             if (left and bottom) then
main.lua:3726:                 TacoTipConfig.custom_pos = { "BOTTOMLEFT", "BOTTOMLEFT", left, bottom }
main.lua:3727:             else
main.lua:3728:                 TacoTipConfig.custom_pos = getDefaultTooltipMoverPosition()
main.lua:3729:             end
main.lua:3730:             syncTooltipMoverPosition(true)
main.lua:3731:             refreshOptionsUI()
main.lua:3732:         end
```

Writes **`TacoTipConfig.custom_pos` only** (never `custom_anchor`, never any
unit field). Registered `main.lua:3821`–`3823`.

### 3.2 Every other writer (exhaustive, both files + gearscore)

| Site | Field(s) written | When |
|---|---|---|
| `main.lua:3726` | `custom_pos = {BOTTOMLEFT,BOTTOMLEFT,left,bottom}` | drag stop (the save) |
| `main.lua:3728` | `custom_pos = {BOTTOMRIGHT,BOTTOMRIGHT,0,0}` | drag stop with nil coords (fallback) |
| `main.lua:3812-3814` | `custom_pos = default` if nil | OnDragStart, before first save |
| `main.lua:3862-3864` | `custom_pos = default`, `custom_anchor = "TOPLEFT"` if nil | `_Enable` (turning feature on) |
| `main.lua:3867-3869` | `custom_anchor = "TOPLEFT"` if nil | `_Enable` |
| `main.lua:3735-3744` | `custom_anchor` cycle TOPRIGHT→BOTTOMRIGHT→BOTTOMLEFT→CENTER→TOPLEFT→… | middle-click on handle |
| `main.lua:3897` | `custom_pos = default` | `_ResetPosition` (Reset button) |
| `main.lua:3921-3923` | `custom_pos = nil`; `custom_anchor = nil` unless `preserveAnchor` | `_Disable` |
| `main.lua:3570-3575` | `custom_pos = nil` if legacy `{TOPLEFT,TOPLEFT,0,0}` | `ADDON_LOADED` version-upgrade migration |
| `main.lua:3582-3586` | `custom_pos = nil` if entries not string/number | `ADDON_LOADED` sanitizer |
| `options.lua:2495-2496` | `custom_pos = {anchor,anchor,0,0}` (or keeps existing / nil on untick) | "Custom Tooltip Position" checkbox |
| `options.lua:2498` | `anchor_mouse = false` | same checkbox, tick-on |
| `options.lua:2510-2513` | `anchor_mouse = value`; `custom_pos = nil` + `_Disable(true)` on tick-on | "Anchor to Mouse" checkbox |
| `options.lua:2540` | `custom_anchor = value` | anchor dropdown |
| `options.lua:391-393` | `_Disable(true)` + `custom_pos = nil` | `/tacotip default` (final slash handler) |
| `options.lua:411-427` | `custom_anchor` = literal | `/tacotip anchor <point>` |
| `options.lua:279-292` | `_Disable()` then `TacoTipConfig = TT:GetDefaults()` | `resetCfg` (reset button / `/tacotip reset`) |
| `gearscore.lua:56-61` | `_Disable(true)` + `custom_pos = nil` | bootstrap `/tacotip default` (before options.lua replaces the handler) |

Key save-side quotes beyond 3.1:

```lua
options.lua:2495:             local anchor = TacoTipConfig.custom_anchor or "TOPLEFT"
options.lua:2496:             TacoTipConfig.custom_pos = value and (TacoTipConfig.custom_pos or { anchor, anchor, 0, 0 }) or nil
```
```lua
gearscore.lua:56:         elseif (cmd == "default") then
gearscore.lua:57:             if (TacoTipDragButton and TacoTipDragButton._Disable) then
gearscore.lua:58:                 TacoTipDragButton:_Disable(true)
gearscore.lua:59:             end
gearscore.lua:60:             if (TacoTipConfig) then
gearscore.lua:61:                 TacoTipConfig.custom_pos = nil
gearscore.lua:62:             end
```

Note `options.lua:2496` re-save shape: enabling the checkbox with no prior drag
stores `{TOPLEFT,TOPLEFT,0,0}` (when `custom_anchor` is default) — the exact
shape the `ADDON_LOADED` migration at `main.lua:3570-3575` clears on the next
**version upgrade**, which falls the tooltip back to the bottom-right default
handle position.

### 3.3 How the saved position reaches the handle

`syncTooltipMoverPosition`, `main.lua:2884`–`2896` (handle ← config; the
tooltip then follows the handle):

```lua
main.lua:2889:     local pos = (TacoTipConfig and TacoTipConfig.custom_pos) or getDefaultTooltipMoverPosition()
main.lua:2890:     TacoTipDragButton:ClearAllPoints()
main.lua:2891:     TacoTipDragButton:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
```
with default `{ "BOTTOMRIGHT", "BOTTOMRIGHT", 0, 0 }` (`main.lua:2881`).
Handle creation applies the same at `main.lua:3706`–`3712`.

**No save/re-save writer reads any unit or cache field.** The two states meet
only at the read side (§4).

---

## 4. RE-HOVER TRACE — and the cached-unit hypothesis, answered

### 4.1 Plain re-hover (mouse left, came back)

**R1.** `UnitFrame_OnLeave` → `GameTooltip:FadeOut()`/`Hide()` (client,
`UnitFrame.lua:442-447`). OnHide → `main.lua:2737-2745`: `isUnitFramePeriodicUpdate`
false now (owner.UpdateTooltip nil'd at `UnitFrame.lua:443`) →
`clearTooltipVisuals(..., "hide")`: **`generation` bumps, timers cancel,
`currentItemLink` nil'd — `currentUnitGUID` stays** (§1.4). The GameTooltip's
point **stays anchored to the handle** (nothing cleared it).

**R2.** Mouse re-enters → identical to Hop 1–9: `SetDefaultAnchor` original
parks bottom-right → post-hook (`main.lua:2840-2842`) re-pins to the handle →
`SetUnit` → render. Cache write at `1630` compares `previousGUID` (still set,
same unit) → `keepModel = true` → no portrait teardown.

So on 0.8.3, **re-hover re-applies the saved position on every hover, via a path
that never consults the cache or the unit.**

### 4.2 While the hover is held (periodic re-fire)

Client `GameTooltip_OnUpdate`
(`origin/classic_anniversary:Interface/AddOns/Blizzard_GameTooltip/Classic/GameTooltip.lua:440-464`):

```lua
	self.updateTooltip = (self.updateTooltip or TOOLTIP_UPDATE_TIME) - elapsed;
	...
	local owner = self:GetOwner();
	if ( owner and owner.UpdateTooltip ) then
		owner:UpdateTooltip();
```
with `TOOLTIP_UPDATE_TIME = 0.2`
(`origin/classic_anniversary:Interface/AddOns/Blizzard_UIParent/TBC/UIParent.lua:1`)
and `self.UpdateTooltip = UnitFrame_UpdateTooltip` latched at
`UnitFrame.lua:454`.

→ **every 0.2 s: full Hop 1 chain again — bottom-right reset then hook re-pin
then SetUnit.** The saved position is re-applied ~5×/second for as long as the
frame is hovered. The addon's OnTooltipCleared/OnHide handlers skip their cache
clear during this loop (R3/R4), which is exactly what keeps `currentUnitGUID`
stable across the SetOwner clears inside those repeats.

### 4.3 Re-render without any anchor call (content-only re-drive)

**GearScore item loads:** `gearscore.lua:398-399` → `TacoTip_GSCallback(tbl.guid)`
→ `main.lua:1260`:

```lua
main.lua:1267:     local ttUnit = resolveTooltipUnit(GameTooltip)
main.lua:1268:     if (not (ttUnit and UnitGUID(ttUnit) == guid)) then
main.lua:1269:         TT.ev.gsCallbackWrongUnit = (TT.ev.gsCallbackWrongUnit or 0) + 1
main.lua:1270:         return
main.lua:1271:     end
...
main.lua:1277:     if (GameTooltip.UpdateTooltip) then
main.lua:1278:         pcall(GameTooltip.UpdateTooltip, GameTooltip)
main.lua:1279:     else
main.lua:1280:         pcall(GameTooltip.SetUnit, GameTooltip, ttUnit)
main.lua:1281:     end
```

(`GameTooltip.UpdateTooltip` is never assigned anywhere in
`origin/classic_anniversary` Interface code — grep returns nothing — so the
`else` branch, `SetUnit`, is the one taken.) The addon states the position
outcome itself, `main.lua:1249`–`1251`:

```lua
main.lua:1249:     -- unbounded, and on a unit frame it shows as the tooltip resetting over and over
main.lua:1250:     -- in the same spot -- the anchor never changes, only the content is rebuilt,
main.lua:1251:     -- many times a second, for as long as the mouse rests there.
```

**Inspect completions:** `INVENTORY_READY`/`TALENTS_READY` → GUID-gated
re-`SetUnit` at `main.lua:3649`–`3666` (quote in §1.3 R7) — same story: content
rebuild, `SetUnit` does not touch the anchor.

**Modifier/target re-renders:** `MODIFIER_STATE_CHANGED` / `UNIT_TARGET` →
`GameTooltip:SetUnit(unit)` after live unit comparison (`main.lua:3540`–`3555`) —
again content only.

### 4.4 Direct answer: does re-apply go THROUGH the cached unit?

**No — not on the saved-position path.** In 0.8.3:

- The **only** saved-position application site is the `SetDefaultAnchor`
  post-hook's `main.lua:2840-2842`. Its gate is `anchor_mouse_spells` (spell
  parents) → `anchor_mouse` → `custom_pos ~= nil` → bottom-right branch. There
  is no `IsUnit`, no `GetUnit`, no `currentUnitGUID`, no "managed/unmanaged"
  classification anywhere in it (grep for `isManagedAnchorTarget`,
  `applyCustomTooltipAnchor`, `runUntainted`, `isAddonAnchorFrame` across the
  whole prior tree: **zero hits**).
- The **cached unit (R1–R4) gates visual clearing only** — portrait teardown,
  timer cancels, class-border state. It never reaches a `SetPoint`.
- The **unit decisions that do touch position** are exactly two, both
  content/mover conveniences:
  1. mover mode (R5, `main.lua:1633-1644`) → `ShowExample` re-anchors to the
     handle — only while the green dot is visible;
  2. `anchor_mouse_spells` early return (`main.lua:2812-2824`) — decides by the
     *parent frame's* `action`/`spellId`, not by any unit or cache.
- Re-save (§3) never reads the unit either. **In 0.8.3 position save and the
  unit cache are parallel states that never intersect**: config holds where the
  tip goes, `_tacoTipState.currentUnitGUID` holds who is being drawn, and the
  hook applies the former unconditionally whenever Blizzard asks for a default
  anchor.

The coupling the operator hypothesised ("resaved from cached unit") does not
exist in 0.8.3 — it first appears in 0.8.4, where `isManagedAnchorTarget` (a
unit/owner classification) can make the hook *skip* the re-apply (§7).

---

## 5. THE RESET / DECAY PATH — everything that changes state over time

### 5.1 Position changes after the initial apply (exhaustive)

1. **Every `SetDefaultAnchor` call re-asserts it** (`main.lua:2840-2846`) —
   hover entry and the 0.2 s `UpdateTooltip` loop. Same value → visually a no-op
   while `custom_pos` is set; **when `custom_pos` is nil the same call re-parks
   the tip at the bottom-right corner** (original function body +
   `main.lua:2844-2846` branch) — this is the literal "resets back to the
   bottom-right corner" mechanic, reachable whenever `custom_pos` is absent.
2. **Spell/action hovers** (anchor_mouse_spells on): `SetOwner(parent,
   ANCHOR_LEFT/RIGHT)` and early return (`main.lua:2816-2823`) — tooltip leaves
   the saved spot *by design* until the next unit `SetDefaultAnchor` puts it back.
3. **Mouse-anchor mode**: cursor follower moves it each frame
   (`main.lua:2794-2806`).
4. **Drag live-repin** (`main.lua:3816-3817`) and `ShowExample`
   (`main.lua:3842-3846`) — mover mode only.
5. **Turn-off / reset paths**: `_Disable` (`main.lua:3906-3908`: hides handle,
   hides tooltip, `GameTooltip:ClearAllPoints()`), `/tacotip default`
   (`options.lua:391-393`, `gearscore.lua:56-61`), `resetCfg`
   (`options.lua:279-292`), `anchor_mouse` tick-on (`options.lua:2512-2513`).
6. **Next-session migration**: legacy `{TOPLEFT,TOPLEFT,0,0}` or
   type-corrupt `custom_pos` cleared at `ADDON_LOADED` (`main.lua:3570-3587`) →
   handle re-created at the bottom-right default (`main.lua:3706-3712`).
7. **Nothing time-based repositions the tooltip in normal play.** The deferred
   work that exists is content-side and generation-guarded: `tooltip_delay`
   render timer (`main.lua:2353-2359`), class-border defer
   (`main.lua:2669-2690`, bails when `state.generation ~= deferralGen`,
   `2674`), border defer (`main.lua:1070-1085` same pattern).

### 5.2 What "after some time" does in 0.8.3 (candidate events, all evidence)

- **Instant fade** (opt-in `TacoTipConfig.instant_fade`): `FadeOut` detoured to
  `Hide()` (`main.lua:3596-3598`), and `UPDATE_MOUSEOVER_UNIT` arms a
  `NewTimer(0, …)` that hides the tip once mouseover is gone
  (`main.lua:3623`–`3640`:

```lua
main.lua:3624:         if (TacoTipConfig.instant_fade and GameTooltip and GameTooltip:IsShown() and ((GameTooltip.IsUnit and GameTooltip:IsUnit("mouseover")) or (GameTooltip.GetUnit and select(2, GameTooltip:GetUnit()) == "mouseover"))) then
main.lua:3625:             cancelFadeTimer(GameTooltip)
...
main.lua:3634:                         if (TacoTipConfig.instant_fade and not UnitExists("mouseover") and GameTooltip and GameTooltip:IsShown() and ...) then
main.lua:3635:                             GameTooltip:Hide()
```

  A hide drops the OnHide clear (§1.4) but **not** the anchor and **not**
  `currentUnitGUID`; the next hover re-runs §4.1 and lands on the saved spot.
- **The 0.2 s `UpdateTooltip` loop** (§4.2) *re-asserts* the saved position
  continuously — if a foreign `SetOwner` (another addon, a Blizzard relative
  anchor) knocked the tooltip off the handle mid-hover, this loop is what puts
  it back ~0.2 s later; when hovering stops, the loop stops.
- **Mover ticker** `NewTicker(1, …)` → `ShowExample()` every second
  (`main.lua:3773-3775`) — only while the green dot is shown; cancelled on
  OnHide of the handle (`main.lua:3799-3801`).
- **Cache decay**: `generation` bumps on every clear/hide (§1.4) invalidate
  deferred callbacks; `currentUnitGUID` never expires — it changes only when a
  different unit renders (`main.lua:1630`) or on `/reload` (frame state gone).

---

## 6. THE SAVE/RESTORE CONTRACT (0.8.3, plain terms)

**Saving.** Position lives in one saved variable: `TacoTipConfig.custom_pos =
{point, relativePoint, x, y}`, pixels against UIParent's BOTTOMLEFT, written at
drag stop from `GetLeft()/GetBottom()` (`main.lua:3723-3726`) — never
`GetPoint()` — plus `custom_anchor` (which corner of the 32×32 handle the tip
hangs on). The handle frame (`TacoTipDragButton`) carries `custom_pos` as its
own placement for the session (`main.lua:2891`, `3712`); it is created hidden
at `ADDON_LOADED` whenever `custom_pos` exists (`main.lua:3588-3590`) and hidden
again after Save (`main.lua:3891`). Feature on/off ⇔ `custom_pos ~= nil`.

**Restoring.** The GameTooltip is anchored *to the handle*
(`SetPoint(custom_anchor or "TOPLEFT", TacoTipDragButton, same)`), and that
re-pin happens inside the `hooksecurefunc` post-hook on
`GameTooltip_SetDefaultAnchor` — which the client fires on every unit-frame
hover and every 0.2 s while hovering (`UnitFrame.lua:452`,
`GameTooltip_OnUpdate`, `TOOLTIP_UPDATE_TIME = 0.2`). The original function's
bottom-right parking is overwritten in the same call. Between hovers nothing
clears the point, so shows that never pass through the hook still appear at the
saved position.

**When it is skipped.** In order: spell/action parent with `anchor_mouse_spells`
on (early return, `2812-2824`); `anchor_mouse` on (cursor follower wins,
`2826-2833`, and the two settings mutually exclude each other in both configs);
`custom_pos` nil → bottom-right branch when `show_hp_bar and show_power_bar`,
otherwise Blizzard's own default stays (`2844-2847`). **No unit check, no
content class, no cache read, no managed-target gate, no taint wrapper.**

**Cache coupling.** The unit cache (`tooltip._tacoTipState`, spine §1) governs
*content* lifecycle only — teardown vs keep on re-render, suppression of
clears during the 0.2 s same-unit loop, deferred-timer invalidation via
`generation`. Position state and cache state are written by disjoint code and
never read each other on the save/restore path; the sole unit-conditioned
re-anchor is mover-mode `ShowExample` (`main.lua:1633-1644` → `3842-3846`),
which cannot run in normal play because Save hides the handle.

**Reset.** `custom_pos` is cleared only by explicit acts (disable slash in two
handlers, checkbox untick, anchor-mouse tick, reset, type-sanitizer,
version-upgrade migration of the legacy `{TOPLEFT,TOPLEFT,0,0}` shape) — never
by time, hover churn, or cache clears.

---

## 7. APPENDIX — factual side-by-side with the current repo (v0.8.4, read-only observation)

No fix proposed; what differs on this path:

| Aspect | Prior `/home/sam/TacoTip/` (0.8.3) | Current repo (0.8.4) |
| --- | --- | --- |
| Hook registration | `main.lua:2863`: body passed **directly** to `hooksecurefunc` | `main.lua:4120-4142`: wrapped in `runUntainted(...)` + `pcall` |
| Non-unit guard | none | `main.lua:4032` `isAddonAnchorFrame(parent/tooltip)` early return |
| **Unit gate** | **none** — applies to every call | `main.lua:4064-4073`: `isManagedAnchorTarget(tooltip, parent)` → `if (not managedAnchor) then … return end` (skips on `"menu"`/`"unresolved"`, counts `TT.ev.anchorSkippedMenu` / `anchorSkippedUnresolved`) |
| Second apply path | none (single site: the hook) | `applyCustomTooltipAnchor(tooltip, unit)` `main.lua:1484-1507`, called at end of the unit render `main.lua:2008-2009` — i.e. **0.8.4's re-apply does run through the resolved unit** |
| Cache | same `_tacoTipState` shape (fields per `main.lua:165-176` in the prior tree; current tree adds fields) | same `currentUnitGUID` write/clear semantics |
| Save side (drag stop, sync, `_Enable/_Save/_ResetPosition/_Disable`, sanitizer, defaults, options/gearscore writers) | §3 of this file | identical logic (current `main.lua:5562+`, `4163-4177`, `5337-5355`) |

The saved-state shape and the handle-anchored restore are unchanged; what 0.8.4
added is (a) conditional **skipping** of the hook re-apply via unit/owner
classification and a taint wrapper, and (b) a unit-gated **second apply site**
later in the render — i.e. the cached/resolved unit *does* now sit in the
re-apply decision, which is precisely the coupling 0.8.3 did not have.
