# Tooltip position save/restore — three-path trace: first hover, re-hover, reset
# (cache lifecycle as the spine) — CURRENT tree vs /home/sam/TacoTip/

- **Desk:** `current-tooltip-save` — revision 2 (supersedes the rev-1 structure; candidate ranking preserved and refined)
- **Date:** 2026-10-22
- **Trees:** CURRENT `/home/sam/TacoTip-Gearscore-TBC/` — TOC 0.8.4, HEAD `db275d7`, DIRTY (`main.lua` 23+/16- width/portrait-edge hunks only; `Tests/harness/tooltip_test.lua` modified). OLD `/home/sam/TacoTip/` — TOC 0.8.3.
- **Scope:** entire shipped addon tree; every hop is quoted file:line, COMMITTED vs UNCOMMITTED noted. No code was modified.

---

## 0. The loop, in one picture

```
SAVE (config, NOT per-unit)                CACHE (per GameTooltip frame)
  drag-stop → TacoTipConfig.custom_pos       tooltip._tacoTipState = {
  options checkbox → custom_pos                generation           (bumped on recycle)
  /tacotip default → custom_pos = nil          currentUnitGUID      (written per render,
                                                                     NEVER cleared)
                                             }
RE-APPLY (per hover)                      CLEAR (per recycle)
  P1: SetDefaultAnchor post-hook            OnTooltipCleared / OnHide
      → isManagedAnchorTarget (LIVE          → isUnitFramePeriodicUpdate (CACHE)
        tooltip unit residue — not the         → clearTooltipVisuals: generation++,
        addon cache) → SetPoint or skip          visuals reset; currentUnitGUID SURVIVES
  P2: unit render → applyCustomTooltipAnchor
      (freshly resolved unit + config only)
```

The operator's hypothesis — "re-apply goes through the cached unit and THAT is what broke" — is tested hop by hop in §3. Verdict in §6.

---

## 1. THE CACHE (spine element)

### 1.1 Definition (COMMITTED; identical shape in both trees)

`main.lua:375-416` (current):
```lua
-- Per-tooltip lifecycle state, stored on the frame as tooltip._tacoTipState.
-- All handles are cleared or invalidated by clearTooltipVisuals on every
-- clear/hide transition.
---@class tacoTipTooltipState
---@field generation integer           -- clear/hide epoch; stale callbacks bail on mismatch
---@field currentUnitGUID string|nil   -- GUID of the unit currently rendered
---@field currentItemLink string|nil   -- item link currently rendered
---@field itemLoadCancel function|nil  -- ItemMixin:ContinueWithCancelOnItemLoad canceler
---@field delayedTooltipTimer table|nil -- cancellable NewTimer handle (unit-tooltip delay)
---@field borderDeferTimer table|nil    -- cancellable NewTimer handle (defensive border re-apply)
---@field classBorderDeferTimer table|nil -- cancellable NewTimer handle (OnShow class-border re-apply)
---@field fadeTimer table|nil           -- cancellable NewTimer handle (instant fade)
---@field inspectState string|nil       -- last inspect answer for this tooltip's unit: ...
local function getTooltipState(tooltip)
    if (not tooltip) then
        return nilTooltipState
    end
    if (not tooltip._tacoTipState) then
        tooltip._tacoTipState = { generation = 0 }
    end
    return tooltip._tacoTipState
end
```
Old tree: same field list at `170`, same `getTooltipState` at `190`. (Current tree adds `portraitSide/portraitAnchored/portraitRightEdge/inspectRenderGUID/inspectRenderTime` at runtime; all both-tree except `portraitRightEdge` bookkeeping emphasis.)

### 1.2 The one WRITE of `currentUnitGUID` (COMMITTED; both trees)

`main.lua:2523-2535` (current), inside `onTooltipSetUnit`, after unit resolution succeeded:
```lua
local guid = (data and data.guid) or UnitGUID(tooltipUnit)
-- Resolve the guid BEFORE clearing, so the clear can tell "this unit changed"
-- from "this is the same unit being re-rendered because a GearScore item load
-- completed". Only the former may tear down the 3D portrait.
local previousGUID = getTooltipState(tooltip).currentUnitGUID
...
clearTooltipVisuals(tooltip, nil, (previousGUID ~= nil and previousGUID == guid), "guid-change")
getTooltipState(tooltip).currentUnitGUID = guid
```
Old tree: identical at `1622-1630`.

### 1.3 `currentUnitGUID` is NEVER CLEARED — both trees, and the code says so

`main.lua:4962-4968` (current; old `3370`):
```lua
-- The old text here read "portrait destroy should be ~1 for a character and
-- 0 for a re-hover of the same one". That is only true for the FIRST unit
-- rendered after a /reload: state.currentUnitGUID is assigned at :1586 and
-- is NEVER cleared, so it always holds the unit rendered most recently --
-- which character you hover first is arbitrary. Re-hovering the same one
-- does not destroy, but only when it is the one still recorded; A, then B,
-- then A again is three destroys, not two.
```
`grep currentUnitGUID` in current main.lua: reads at `1794, 1808, 2503, 2527, 3785`; the single write at `2535`; **no `= nil` anywhere**. Same in old tree (`1598, 1622, 1630, 2705`).

### 1.4 `generation` — the epoch (COMMITTED; both trees)

Bumped only in `clearTooltipVisuals` when `preservePendingItem` is falsy — `main.lua:2191-2200` (current):
```lua
local state = getTooltipState(tooltip)
if (not preservePendingItem) then
    state.generation = state.generation + 1
    cancelItemLoadRefresh(tooltip)
    state.currentItemLink = nil
end

cancelDelayedTooltip(tooltip)
cancelDeferredAppearance(tooltip)
cancelFadeTimer(tooltip)
```
Old tree: `1333` (`generation + 1`); old `cancelDeferredAppearance` lacks the `portraitGuardTimer` cancel that current adds at `2164`.

### 1.5 Who READS the cache (all reads, current tree)

| Read | file:line | Effect |
|---|---|---|
| unresolved-unit keepModel decision | `2500-2503` | no-op vs teardown of visuals — **and early `return` that skips the anchor re-apply** (see §3, hop B3) |
| previousGUID compare on render | `2527-2534` | keepModel for same-unit re-render |
| portrait side cache reset (keepModel gate) | `2227-2230` | `portraitSide/portraitAnchored/portraitRightEdge` reset on recycle |
| portrait guard timer validity | `1793-1808` | bails if `generation` or `currentUnitGUID` changed |
| border defer / class-border timers | `1853, 1866, 3741, 3754` | bail on generation mismatch |
| item-load refresh validity | `3616-3624` | bail on generation/link mismatch |
| **`isUnitFramePeriodicUpdate`** | `3776-3796` | **skips OnTooltipCleared/OnHide recycle bookkeeping when `owner.unit`'s GUID still equals the cached GUID** |
| inspect re-render coalesce | `5475-5490` | `inspectRenderGUID/Time` dedupe |

`isUnitFramePeriodicUpdate` verbatim (current `3776-3796`; old `2691-2712` — IDENTICAL):
```lua
local function isUnitFramePeriodicUpdate(tooltip)
    if (not tooltip) then
        return false
    end
    local owner = tooltip.GetOwner and tooltip:GetOwner()
    if (not owner) then
        return false
    end
    local state = getTooltipState(tooltip)
    local curGUID = state and state.currentUnitGUID
    if (not curGUID) then
        return false
    end
    if (owner.UpdateTooltip and owner.unit and UnitExists and UnitExists(owner.unit)) then
        local uGUID = UnitGUID(owner.unit)
        if (uGUID and uGUID == curGUID) then
            return true
        end
    end
    return false
end
```

---

## 2. SAVE paths (where `custom_pos` is written — config-level, unit-agnostic)

| Writer | file:line | Committed? | Quote/behavior |
|---|---|---|---|
| drag-stop | `main.lua:5581-5605` | COMMITTED | `TacoTipConfig.custom_pos = { "BOTTOMLEFT", "BOTTOMLEFT", left, bottom }`; nil-read keeps previous + `TT.ev.moverSaveFailed` (OLD `3726-3728` stored the DEFAULT corner instead — snap-back bug, fixed in current) |
| `_Enable` seed | `main.lua:5766-5768` | COMMITTED | `custom_pos = getDefaultTooltipMoverPosition()` (= `{ "BOTTOMRIGHT", "BOTTOMRIGHT", 0, 0 }`, `4150-4170`) + `custom_anchor = "TOPLEFT"` when enabling unsaved |
| options checkbox | `options.lua:3094-3104` | COMMITTED | `custom_pos = value and (custom_pos or { anchor, anchor, 0, 0 }) or nil` (old `2492-2503`, same) |
| `_ResetPosition` | `main.lua:5800-5804` | COMMITTED | `custom_pos = getDefaultTooltipMoverPosition()` |
| `_Disable` | `main.lua:5806-5830` | COMMITTED | `custom_pos = nil` (+ `custom_anchor = nil` unless preserve) |
| `/tacotip default` (bootstrap, pre-options.lua) | `gearscore.lua:255-261` | COMMITTED | `_Disable(true)` then `TacoTipConfig.custom_pos = nil` (old `gearscore.lua:61`, same) |
| migration | `main.lua:5337-5343` | COMMITTED | on version change, `{TOPLEFT,TOPLEFT,0,0}` → `nil` (old `3570-3575`, same) |
| sanitizer | `main.lua:5349-5353` | COMMITTED | corrupt entries → `nil` (old `3582-5386`, same) |

**Nothing in any save path reads the unit cache.** The saved position is one global config table, not keyed by unit or GUID.

---

## 3. PATH A — FIRST HOVER (after /reload or from cold)

| Hop | Current (0.8.4) | Old (0.8.3) | Delta |
|---|---|---|---|
| A1. Unit frame `OnEnter` → `SetOwner` → `OnTooltipCleared` fires | `registerTooltipVisualClearing` `3802-3819`: `isUnitFramePeriodicUpdate` → **false** on first hover (`curGUID` nil, `3786-3788`) → `cancelDelayedTooltip` + `clearTooltipVisuals(..., "cleared", true)`; `generation++` | old `2723-2730`, same logic | none |
| A2. `GameTooltip_SetDefaultAnchor(GameTooltip, parent)` → post-hook | `4119-4142`: `runUntainted(pcall(onGameTooltipSetDefaultAnchor))`. Gate `isManagedAnchorTarget` (`3931-4026`) probes **LIVE** tooltip: lines cleared, `GetUnit`/`IsUnit` empty → **`false, "menu"` → SKIP** (`4064-4072`); client leaves its own `BOTTOMRIGHT` placement | old `2811-2852`, `2862-2863`: **NO gate** — `custom_pos` branch re-anchors to the handle for EVERY tooltip, directly inside `hooksecurefunc` | **BREAK-SITE class introduced: ungated → gated** |
| A3. `SetUnit` → `OnTooltipSetUnit`/post-call → `handleTooltipSetUnit` (`3335-3351`, `tooltip_delay` deferral) → `onTooltipSetUnit` | resolve live (`2443-2454` → `resolveTooltipUnit` `1316-1428`); write `currentUnitGUID` (`2535`); `TT:ApplyTooltipAppearance` (`3311`) → **`applyCustomTooltipAnchor(tooltip, unit)` (`2009`, config-only checks `1484-1507`) → SetPoint to handle → SAVED POSITION APPLIED** | old render: `ApplyTooltipAppearance` ends after bar texture — **no SetPoint anywhere** | current ADDED render-time anchor as the gate's compensation |
| A4. `OnShow` → `onTooltipShow` (`3678-3772`) | portrait side + border only; never SetPoints the tooltip | old `2610+`, same role | none |

**Path A outcome: both trees show the tooltip at the saved position.** First hover cannot distinguish them — the compensation works when the render completes.

---

## 4. PATH B — RE-HOVER (the broken path)

| Hop | Current (0.8.4) | Old (0.8.3) | Delta |
|---|---|---|---|
| B1. Re-`SetOwner` → `OnTooltipCleared` | `isUnitFramePeriodicUpdate` now reads a **populated, never-cleared** `currentUnitGUID` (`1.3`): for a unit-frame-owned tooltip whose `owner.unit` GUID still matches (same target re-entered, PlayerFrame, etc.) it returns **true** → recycle bookkeeping **SKIPPED** (`3813-3815`): no `generation++`, no timer cancels, no portrait-latch reset | IDENTICAL (`2691-2712` + old `2723-2730`) | none (aligned) — but this is the hop where the cache first diverges first-hover vs re-hover behavior in BOTH trees |
| B2. `SetDefaultAnchor` → gated hook | Gate probes **LIVE residue**: after `SetOwner`'s reset the unit fields are usually empty → `"menu"` → **SKIP** → client `BOTTOMRIGHT` (documented at `1469-1479`: "the hook returns untouched, and the tooltip stays where the client put it -- the bottom-right corner"). If residue still answers (`IsUnit`/`GetOwner().unit`/`parent.unit`, `3987-4021`) → gate passes → re-anchor. **Answer is nondeterministic across hovers.** | **No gate: every re-hover re-anchors at the hook, before `SetUnit`, unconditionally.** | **THE PRIME BROKEN HOP.** Current removed the unconditional re-apply and made the hook's answer depend on live tooltip residue |
| B3. Render → `applyCustomTooltipAnchor` | Reaches `2009` ONLY if `onTooltipSetUnit` passes all early returns: unresolved unit (`2519-2520` — and this branch's keepModel decision **reads the cache**: `changeUnproven = (incomingGUID == nil) or (incomingGUID == unresolvedState.currentUnitGUID)`, `2502-2503`; on the Classic family `data` is nil every render so `changeUnproven` is always true); empty `text[1]` (`2623`); player with empty `text[2]` (`2624`). Any early return → **no re-apply this hover** | Render never anchored; position depended solely on the (ungated) hook — early returns were position-irrelevant | Current made the position RENDER-DEPENDENT; the cache participates only in the unresolved branch's keepModel, but that branch **returns without anchoring either way** |
| B4. Async re-drives during the hover | `TacoTip_GSCallback` (`main.lua:2093-2147`): branches on **LIVE** `resolveTooltipUnit(GameTooltip)` + `UnitGUID(ttUnit) == guid` (`2122-2126`) — not the addon cache — then `GameTooltip.UpdateTooltip()` or `GameTooltip:SetUnit(ttUnit)` → full render → **re-apply runs** | old `1260-1289`: same live-resolve guard + re-drive (current adds only the player-pane repaint before the guard) | aligned; B4 is a RECOVERY path — matches "after some time it [position] fixes/resets" when item loads complete |
| B5. Event re-drives | `UNIT_TARGET` `5314-5323`, `MODIFIER_STATE_CHANGED` `5301-5313`, `INVENTORY_READY/TALENTS_READY` `5459-5492` — all `GameTooltip:SetUnit(...)` → render → **re-apply runs** | old `3642-3688` same events | aligned |

**Path B outcome:** OLD — position re-applied at hop B2 on every re-hover, full stop. CURRENT — B2 skips nondeterministically and the fallback (B3) can be skipped by three early returns; the tooltip sits at the client placement (bottom-right) until a B4/B5 re-drive completes a render. This is "first hover OK, re-hover stuck, resets later", hop-accurate.

---

## 5. PATH C — RESET ("after some time it resets")

| Leg | Mechanism | file:line (current) | Cache role | Old |
|---|---|---|---|---|
| C1. Reset TO SAVED position | Any completing render: GS item loads (`B4`), inspect ready (`5459-5492`), `UNIT_TARGET`, Shift modifier, next clean hover | via `2009` | none (fresh resolve) | N/A — old never lost the position, so no "reset to saved" was observable |
| C2. Reset TO BOTTOM-RIGHT | Any `SetDefaultAnchor` re-fire without a completing render while the gate says skip: "anchor re-fire with cached text" is a documented real case (`3670-3671`: "a re-show skipped OnTooltipSetUnit (e.g. anchor re-fire with cached text)"); also any early-return render (B3) | `4064-4072` skip; `3671`; `2519/2623/2624` | indirect: never-cleared `currentUnitGUID` keeps B1's recycle-skip armed for the whole session | impossible (ungated hook) |
| C3. Tooltip hidden while state survives | instant fade: `UPDATE_MOUSEOVER_UNIT` → `fadeTimer` → `GameTooltip:Hide()` (`5440-5457`); `FadeOut` post-hook hide (`5367-5384`) | `OnHide` → `isUnitFramePeriodicUpdate` (cache!) → may skip `clearTooltipVisuals` (`3826-3837`); even when it runs, `currentUnitGUID` survives (`1.3`) | **the cache is exactly why the next hover (Path B) starts with residue** | same structure (old `3623-3641`, `3592+`) |
| C4. Feature-level reset (position feature off) | migration `5337-5343`, sanitizer `5349-5353`, `/tacotip default` (`gearscore.lua:255-261` bootstrap; options.lua final handler `731-741`), `_Disable` `5825` — any of these NILS `custom_pos` → every subsequent hover falls to the client/two-bar `BOTTOMRIGHT` (`4092-4095`) | config, no cache | same in old |

---

## 6. Verdict on the operator's hypothesis

**"Re-apply goes through the cached unit and THAT is what broke."**

- **The SetPoint itself does NOT read the addon cache.** `applyCustomTooltipAnchor` (`1484-1507`) checks only `TacoTipConfig`, `TacoTipDragButton`, and that `unit` is a non-empty string — the unit is freshly resolved in the same render (`2443-2454`), never taken from `_tacoTipState`.
- **The gate does NOT read the addon cache either** — `isManagedAnchorTarget` (`3931-4026`) probes LIVE tooltip methods + `UnitExists`. What it reads is the *client's* tooltip residue (previous unit), which the addon's own comment flags as unreliable at hook time (`1469-1479`).
- **The addon cache DOES branch three things that shape the symptom**, all via the never-cleared `currentUnitGUID`:
  1. **Hop B1** — `isUnitFramePeriodicUpdate` (`3776-3796`) makes re-hover skips the recycle bookkeeping (both trees; not a regression, but the reason re-hover ≠ first hover in state terms).
  2. **Hop B3** — the unresolved-unit early return's keepModel decision (`2502-2503`) reads the cache; the branch returns **without re-applying the anchor** regardless of the decision — so a resolution failure on re-hover costs the position in current, while in old it cost nothing positionally.
  3. **Hop C3** — cache survival across hide is what arms Path B's residue on the next hover.

**Refined verdict:** the broken hop is B2 (unconditional hook re-apply → residue-dependent gated skip, introduced in committed `db275d7`), amplified by B3 (render-early-return blindness introduced by making the render the only compensation). The cached unit is a *contributing state* (B1/C3), not the re-apply's data source.

### Ranked causes (rev-2 ranking, consistent with rev 1)
1. **B2 — gated hook** (prime): ungated in 0.8.3, residue-dependent skip in 0.8.4; skip leaves the client `BOTTOMRIGHT` placement live for the whole hover.
2. **B3 — render compensation skippable**: early returns `2519/2623/2624` and `tooltip_delay` deferral (`3337-3347`) remove the only remaining re-apply.
3. **C2/B4 timing** — "resets later" = async re-drive (GS item loads `2093-2147`, inspect `5459-5492`) completing a render and jumping the tooltip back; the reset target being bottom-right is the client placement the B2 skip left behind.
4. **runUntainted/pcall silent failure** (`4120-4141`, `579-587`) — check `/tacotip diag`: `TT.ev.anchorHookFailed`, `anchorSkippedMenu/Unresolved` (`4816-4817`) vs `unitRender`.
5. **Uncommitted hunks** (width memo, `getPortraitSideRightEdge` clamp removal, `portraitRightEdge` reset) — portrait-side only; no tooltip SetPoint.

---

## 7. Files the loop touches + load order (`.toc`)

`TacoTip.toc` (current): `Libs\...` → `Locale\...` → **`gearscore.lua` → `pawn.lua` → `textures.lua` → `options.lua` → `main.lua`**. `## SavedVariables: TacoTipConfig`.

- **gearscore.lua** (loads FIRST of the core files): bootstrap slash handler `240-275` (`/tacotip custom|save|default`; `default` nils `custom_pos` at `260`) — superseded once options.lua's final handler loads (`main.lua:5842-5855` explains the hand-off); GS item-load ring fires `TacoTip_GSCallback(tbl.guid)` (`642-643`).
- **options.lua** (loads BEFORE main.lua): DEFAULTS `211-242` (`anchor_mouse=false`, `anchor_mouse_spells=false`, `custom_anchor="TOPLEFT"`, `tooltip_delay=0`); `custom_anchor` sanitizer `463-475`; final slash `/tacotip …` `701-753` (protected `_Save`/`_Disable`); checkbox writes `3094-3116`; anchor dropdown `3140-3143`; refresh `3209-3219`.
- **main.lua**: everything quoted above; defines global `TacoTip_GSCallback` (`2093`) and `TacoTip_CustomPosEnable` (`5561`) that the earlier files call through guards.
- **pawn.lua / textures.lua / Locale\\***: no position/cache touchpoints (whole-tree grep).
- **TacoTip_Extras/**: whole-dir grep for `GameTooltip:SetOwner|SetPoint|ClearAllPoints|GameTooltip_SetDefaultAnchor|custom_pos` — **zero matches**; Extras is not in this loop.
- **Tests/, Tools/, OLD/, desks/, bench/**: not shipped.

---

*End of trace. No code was modified. Evidence only.*
