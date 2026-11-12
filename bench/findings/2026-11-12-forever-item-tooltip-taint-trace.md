# Forever item-tooltip taint trace — 2026-11-12

## Symptom

On the Camelot client (Forever 16001) an item tooltip is missing the client's
own **right-column** segments: the item subclass (`Staff`) and the weapon speed
(`Speed 3.20`), on every item. The operator cannot reproduce it; other users
report it, apparently in instances / combat / encounters. No Lua error is
reported in the `/tt diag` report (errors caught: 0).

## What the client source says (origin/forever, 1.60.1)

| fact | evidence |
| :--- | :--- |
| Reading a tooltip's info from a tainted hook can carry taint into `ProcessInfo`; taint + **secret line data** can make the tooltip display **no lines**. The client therefore wraps that read in `securecallfunction`. | `Blizzard_GameTooltip/Mainline/GameTooltip.lua:994-1003` |
| The tooltip-data accessors (`SetUnit`, `SetItemByID`, `SetLootItem`, …) are **secure delegates**: they run untainted and "taint is removed from all supplied arguments". They only launder what the addon actually hands them. | `Blizzard_SharedXMLGame/Tooltip/TooltipDataHandler.lua:489-505` |
| Post-calls registered through `TooltipDataProcessor.AddTooltipPostCall` are dispatched through a forbidden attribute delegate — i.e. the addon callback is attached to the client's own pipeline. | `TooltipDataHandler.lua:141-153`, `:199-201`, `:298` |
| `C_Item.GetItemInfo` is `MayReturnNothing` + `SecretArguments="AllowedWhenUntainted"`. The **argument** is gated; the returns carry no secret predicate and the whole list is absent while uncached. | `Blizzard_APIDocumentationGenerated/ItemDocumentation.lua:626-640` |
| `GameTooltip` has **no** `UpdateTooltip` method on this client: `GameTooltip_OnUpdate` routes to the owner's `UpdateTooltip`, else `self.RefreshData`. | `Blizzard_GameTooltip/Mainline/GameTooltip.lua:450-460` |

The last row matters for the trace: TacoTip's item-load repaint
(`scheduleItemTooltipRefresh` → `pcall(tooltip.UpdateTooltip, tooltip)`) is a
**silent no-op on Forever**, not a taint vector and not a repaint.

## TacoTip item path (pre-fix)

```
TooltipDataProcessor Item post-call
└─ safeItemToolTipHook → safeCall(itemToolTipHook)
   ├─ isForeverLootTooltip            → return (already native-safe)
   ├─ clearTooltipVisuals("item")
   ├─ resolveTooltipItem
   │  ├─ tooltip:GetItem()                    ← tooltip-INFO read
   │  ├─ TooltipUtil.GetDisplayedItem()       ← tooltip-INFO read
   │  └─ TT.tooltipDataReadable(data) → data.*  (sanctioned payload)
   ├─ C_Item.IsEquippableItem  (pcall + guard)
   ├─ C_Item.GetItemInfo       (pcall, but result fields not all tested)
   ├─ AddLine  ilvl / GearScore / HunterScore
   └─ applyTooltipFonts / Backdrop / MaxWidth  (no tooltip-info reads)
OnShow hook
└─ onTooltipShow
   ├─ tooltip:GetItem()                       ← tooltip-INFO read
   └─ resolveTooltipUnit → GetDisplayedUnit / tooltip:GetUnit   ← INFO reads
```

The loot-window tooltip was already excluded from all of this. Every other item
tooltip still performed four tooltip-info reads per render — exactly the class
of read the client's comment warns about, which is the only mechanism in the
source that can drop a secret-bearing line subset.

## Fix (this round)

1. `gearscore.lua` — the file-scope `GetItemInfo` wrapper now sits below the
   strong `isSecretValue` guard, rejects a secret link before the call, pcalls
   the call, and answers `nil` (every caller's existing "not cached" shape)
   when it refuses. Returns stay positional (slot 9 = itemEquipLoc).
2. `main.lua` — on Forever the item post-call resolves its link from the
   `data` payload only (`resolveTooltipItem(..., payloadOnly=true)`); the two
   tooltip-info reads are skipped there and kept byte-identical on the classic
   families, which have no payload.
3. `main.lua` — the item post-call marks the tooltip in its per-tooltip state;
   `onTooltipShow` uses that marker to skip `GetItem` and `resolveTooltipUnit`
   for item tooltips on Forever. `clearTooltipVisuals` resets the marker, so
   no other tooltip type inherits it.
4. `main.lua` — comment only: the item-load repaint is a no-op on the
   data-pipeline clients (no `UpdateTooltip` method).

## Pins

- `forever_tooltip_test.lua` P-ITEM (10 checks): the item post-call performs no
  tooltip-info read; rows still come from the payload; `OnShow` performs none;
  a secret link (throwing `issecretvalue`) neither raises nor adds a row.
  FOREVER pins 144 → 154.
- `contract_pins_test.lua` H (2 checks): a secret link never reaches
  `C_Item.GetItemInfo` (0 calls, score 0); a refused call answers 0 instead of
  raising. CONTRACT pins 62 → 64.

Red proof: `TACOTIP_MAIN_OVERRIDE` at HEAD fails 3 P-ITEM checks (reads=1,
reads=2, secret link scores 100); `TACOTIP_GS_OVERRIDE` at HEAD fails the
refusal check (`ok=false`).

## Residual (not changed this round)

- The item-path counters and the `secret restrictions` row now ship in `/tt diag`
  (`item tooltip hooks`, warn on any unreadable payload or dropped secret link).
- TacoTip still **adds** up to three left rows and re-fonts/re-widths an item
  tooltip whose line set may be secret. The reads are now gone, so the client's
  own render is untouched; if users still report the missing right column, the
  next step is to skip the whole item hook on Forever when its payload is not
  provably readable (`TT.tooltipDataReadable(data) == false`).
- Unit tooltips were out of scope for this trace and are unchanged.
