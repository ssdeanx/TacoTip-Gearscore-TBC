# Tooltip geometry audit — decisions taken from a rect that is not final

Date: 2026-10-21
Scope: TacoTip 0.8.4 tooltip appearance and position path, plus TacoTip Extras.
Trigger: operator report — the portrait stopped flipping to the left when the
tooltip reached the screen edge, and was "pulled just off screen"; then "works on
the first hover after a reload, stuck off screen after that"; suspected on
players too.

## The class of bug

Any decision made from **screen geometry during the unit render** is suspect on
this addon, for two independent reasons:

1. The client sets the tooltip's anchor **before** it tells the tooltip which
   unit it is showing, and the addon's saved anchor is applied at the **end** of
   `TT:ApplyTooltipAppearance`. So a `GetRight()/GetLeft()/GetTop()/GetBottom()`
   read in the middle of that function measures the **client's** position, not
   the addon's.
2. On Retail and WoW Forever the whole unit handler runs from the
   `TooltipDataProcessor` post-call, which fires **before** the client's own
   `Show()` — the frame has no rect at all (`GetRight()` is 0). On the classic
   family the render runs inside `SetUnit`, also before `Show()`.

Anything that only *anchors* a child to the tooltip is immune: the child moves
with the tooltip. The exposure is **decisions**, i.e. reads used to choose an
anchor side or an offset.

## Inventory — every geometry read on the path

| site | reads | verdict |
| :--- | :--- | :--- |
| portrait side (old) | `tooltip:GetRight()` vs `UIParent:GetRight()` | **defect** — measured the client's corner; see below |
| `getPortraitSideRightEdge` | `TacoTipDragButton:GetLeft/GetWidth`, `tooltip:GetWidth()` | sanctioned: answers where the tooltip is *about to* be |
| `applyTooltipPortraitSide` (Show) | same helper | sanctioned: the one point where width and rect are final |
| cursor follower (`CreateMouseAnchor` OnUpdate) | `GetCursorPosition`, `UIParent:GetEffectiveScale` | intentional — that is what mouse mode is |
| `anchor_mouse_world` branch | `GetMouseFocus()` | intentional — chooses between cursor and saved position only |
| drag-stop save | `self:GetLeft()`, `self:GetBottom()` | guarded (nil keeps the saved value, counts `moverSaveFailed`) |
| power bar | `SetPoint` relative to `GameTooltip` | follows the tooltip; no read |
| status bar | `GameTooltipStatusBar`, relative | follows the tooltip; no read |
| spec icon / border / backdrop | relative / `SetAllPoints` | follows the tooltip; no read |
| mover example (`ShowExample`) | anchors `GameTooltip` directly to the handle | consistent with the saved position |
| TacoTip Extras | no tooltip `GetRight/GetLeft/GetTop/GetBottom`, no `GameTooltip:SetPoint` | clean |

`IsShown()` reads: only the portrait-side decision uses it as a decision input
(the side is per-show); every other use is show/hide plumbing.

## The defect

The side was decided inside the render:

```lua
cachedSide = (tooltipRight > 0 and tooltipRight >= screenWidth) and "left" or "right"
```

with `tooltipRight = tooltip:GetRight()`. At that moment the tooltip still sat
where the client had put it — `BOTTOMRIGHT` of `UIParent` on Classic Era
(`origin/classic_era:Blizzard_GameTooltip/Classic/GameTooltip.lua:109-114`), the
owner frame on live — so the edge was always *inside* the screen, the side was
almost always `"right"`, and `applyCustomTooltipAnchor` then moved the tooltip to
its saved edge with the portrait already outside.

Two follow-on mechanisms made it look inconsistent:

- **Unit frames vs world hovers.** A unit frame passes the client's
  `GameTooltip_SetDefaultAnchor(GameTooltip, self)` **before** `SetUnit`, so the
  addon's post-hook had already put the tooltip on the saved position and
  `GetRight()` measured the truth. A world/mouseover unit fails that hook's gate
  (the tooltip still describes the previous unit), so it measured the corner.
  That is the "only units, not players" half of the report.
- **Cache.** The side is cached per tooltip and only re-decided on a recycle, a
  scale/invert change, or the first shown frame. A wider tooltip on a later
  hover kept the first hover's side for the life of the `GameTooltip` — the
  "first hover after a reload is fine, then stuck" half.

Late width growth (TacoTip Extras appends rows **after** the render, and the
inspect/GearScore path adds lines after `Show`) is the player-side variant: the
width measured during the render is the narrow one.

## Fix

1. `getPortraitSideRightEdge(tooltip)` answers the tooltip's right edge **as it
   will be** when the addon owns the position: `custom_anchor` on the handle plus
   the tooltip's width (`LEFT` → `left + width`, `RIGHT` → `right`,
   `CENTER` → centres coincide). Falls back to `GetRight()` when it does not own
   the position. Second return says which source answered, because only the
   anchor-derived edge may be a cache key — the cursor follower moves the tooltip
   every frame, and keying on that would re-anchor the portrait per render, the
   per-render anchor 0.7.9 removed.
2. The edge is part of the side-cache key (`portraitRightEdge`, rounded), so a
   wider tooltip re-decides without a recycle.
3. The side decision is extracted into `applyTooltipPortraitSide` and called
   **again from `OnShow`** — the one frame where every line is in (ours,
   Blizzard's, Extras') and the rect is final. It mutates only the addon's
   portrait, never the tooltip.

## Pins (revert-to-fail, all five clients)

| claim | revert | failure seen |
| :--- | :--- | :--- |
| saved position at the edge flips the portrait left | helper → `tooltip:GetRight()` | `point=TOPLEFT` |
| a wider tooltip re-decides without a recycle | drop the edge key | `point=TOPLEFT` |
| rows appended after the render are measured at Show | drop the OnShow call | `before=TOPLEFT after=TOPLEFT` |
| mouse mode does not re-anchor per render | key on the edge always | `anchored 5 time(s) across 5 renders` |
| no future geometry read in the render | inject `tooltip:GetRight()` | `geometry read in the render: :GetRight%(` |

The last one is a source scan in `Tests/harness/load_test.lua`: the body of
`TT:ApplyTooltipAppearance` is read from disk and must contain no
`GetRight/GetLeft/GetTop/GetBottom/GetWidth/GetHeight` call. It is the tripwire
for this whole class.

## Deliberately unchanged

- Mouse-anchor mode keeps its once-per-show side. It already follows the cursor
  every frame; a per-frame side decision would reintroduce the 0.7.9 anchor
  churn.
- The `>= screenWidth` boundary (right edge against the screen edge) is kept
  exactly as it was.
- Nothing in the position path was reordered; the saved anchor is still applied
  at the end of the render.

## Residual risk

- `applyTooltipPortraitSide` at `OnShow` is a new call site. It is wrapped in the
  existing `runUntainted` OnShow hook, touches only the portrait, and is a cache
  hit unless scale/invert/edge/show state changed.
- A tooltip that grows **after** `Show` and never renders again (item data
  arriving late) would keep the show-time side until the next render. The
  inspect path re-renders through `GameTooltip:UpdateTooltip`, and the client's
  periodic unit-frame update re-renders for unit frames, so this window is one
  update at most.
