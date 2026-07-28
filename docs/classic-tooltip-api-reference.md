# GameTooltip API Reference — Classic Era / TBC Anniversary

> **Source:** Blizzard UI source (`wow-ui-source`), branches `origin/classic_era` (1.15.9, build 68940) and `origin/classic_anniversary` (2.5.6, build 68941).
> **API surface is identical** on both branches.

## How to read this document

Each method has:

- **Signature** — the Lua call pattern
- **Available on** — which tooltip frame types support it
- **What it does** — from Blizzard's own source and API docs
- **Currently used?** — whether TacoTip calls it today
- **How we could use it** — concrete improvement opportunities

---

## 1. Line Access Methods

### `tooltip:GetLeftLine(line)`

| Field | Value |
| ----- | ----- |
| **Signature** | `tooltip:GetLeftLine(line: luaIndex) -> SimpleFontString` |
| **Available on** | `GameTooltip`, `ItemRefTooltip`, `ShoppingTooltip`, `WorldMapTooltip` |
| **Doc** | `FrameAPITooltipDocumentation.lua` — documented, Environment: All |
| **Currently used?** | ❌ TacoTip uses `_G["GameTooltipTextLeft"..i]` instead |
| **Blizzard usage** | `self:GetLeftLine(numLines)` — returns FontString at numeric line |

**How we could use it:**

Replace every `_G["GameTooltipTextLeft"..i]` in `main.lua` with `tooltip:GetLeftLine(i)`. This:

- Eliminates global-table lookup (`_G`) — faster, no string concat
- Works on **any** GameTooltip variant regardless of font string naming
- Is the official Blizzard API — guaranteed to be forward-compatible

**Current `_G` sites to refactor (main.lua):**

| Line | Current code | Could be |
| --- | --- | --- |
| ~728 | `_G[frameName.."TextLeft"..i]:GetText()` | `tooltip:GetLeftLine(i):GetText()` |
| ~730 | `_G["GameTooltipTextLeft"..i]` | Same pattern |
| ~169 (clearTooltipGuildLine) | `_G[name.."TextLeft"..lineIdx]` | `tooltip:GetLeftLine(lineIdx)` |

### `tooltip:GetRightLine(line)`

| Field | Value |
| --- | --- |
| **Signature** | `tooltip:GetRightLine(line: luaIndex) -> SimpleFontString` |
| **Available on** | Same as `GetLeftLine` |
| **Doc** | `FrameAPITooltipDocumentation.lua` — documented, Environment: All |
| **Currently used?** | ❌ Never used in TacoTip |

**How we could use it:**

If we ever display right-aligned text (e.g., gear score on the right side of a tooltip line), this is how Blizzard reads right-side font strings. Currently the addon only writes to left font strings.

---

## 2. Unit Queries

### `tooltip:IsUnit(unitToken)`

| Field | Value |
| --- | --- |
| **Signature** | `tooltip:IsUnit(unitToken: string) -> boolean` |
| **Available on** | `GameTooltip` |
| **Doc** | Undocumented C++ method (used in `GameTooltip.lua:928`) |
| **Currently used?** | ❌ TacoTip uses `resolveTooltipUnit()` which does more work |
| **Blizzard usage** | `if self:IsUnit("mouseover") then ... end` — checks if tooltip matches a unit |

**How we could use it:**

Simplifies the `OnTooltipSetUnit` guard. Instead of calling `GetUnit()` + `UnitExists()`:

```lua
-- Current (resolveTooltipUnit):
local ok, unit, unit2 = pcall(tooltip.GetUnit, tooltip)
if ok and unit then ...

-- Could be (simpler):
if tooltip:IsUnit("mouseover") then ...
```

**Note:** `IsUnit` only answers "this tooltip IS showing unit X" — it doesn't tell you *which* unit like `GetUnit` does. It's useful as a guard, not a replacement for `resolveTooltipUnit` entirely.

---

## 3. Owner Queries

### `tooltip:GetOwner()`

| Field | Value |
| --- | --- |
| **Signature** | `tooltip:GetOwner() -> frame or nil` |
| **Available on** | `GameTooltip`, all tooltip frames |
| **Doc** | Undocumented C++ method (used in `GameTooltip.lua:196,199`) |
| **Currently used?** | ❌ Never used in TacoTip |
| **Blizzard usage** | `local owner = self:GetOwner()` — check who owns the tooltip |

**How we could use it:**

- **Bleed prevention:** In `clearTooltipVisuals`, check if the owner is a unit-producing frame before touching unit-specific overlays. If `tooltip:GetOwner()` returns nil or a non-unit frame, skip class borders / portraits / guild lines.
- **Debug logging:** Log which frame triggered the tooltip.

---

## 4. Width / Padding Methods

### `tooltip:GetMinimumWidth()`

| Field | Value |
| --- | --- |
| **Signature** | `tooltip:GetMinimumWidth() -> width: number, forced: boolean` |
| **Available on** | `GameTooltip` |
| **Doc** | `FrameAPITooltipDocumentation.lua` — Environment: All |
| **Currently used?** | ❌ TacoTip always sets min width unconditionally |
| **Blizzard usage** | `if frame:GetMinimumWidth() < frameWidth then frame:SetMinimumWidth(frameWidth) end` |

**How we could use it:**

Instead of always setting `SetMinimumWidth(0)` unconditionally, read the current value first and only change when necessary:

```lua
local currentMin = tooltip:GetMinimumWidth()
if currentMin ~= 0 then
    tooltip:SetMinimumWidth(0)
end
```

### `tooltip:SetMinimumWidth(width, force)`

| Field | Value |
| --- | --- |
| **Signature** | `tooltip:SetMinimumWidth(width: number, force: boolean)` |
| **Available on** | `GameTooltip` |
| **Doc** | `FrameAPITooltipDocumentation.lua` — Environment: All |
| **Currently used?** | ✅ Already used (guarded: `tooltip.SetMinimumWidth`) |

`force=true` enforces the width even if content is narrower. Default is `false` (tooltip can grow wider).

### `tooltip:SetPadding(right, bottom, left, top)`

| Field | Value |
| --- | --- |
| **Signature** | `tooltip:SetPadding(right: number, bottom: number, left: number, top: number)` |
| **Available on** | `GameTooltip` |
| **Doc** | Used in `SharedTooltipTemplates.lua` — undocumented C++ |
| **Currently used?** | ❌ Never used in TacoTip |

**How we could use it:**

If we add visual elements that change tooltip dimensions (e.g., a gear score bar), we may need to adjust padding. Blizzard calls:

```lua
self:SetPadding(style.padding.right, style.padding.bottom, style.padding.left, style.padding.top)
```

### `tooltip:ClearPadding()`

| Field | Value |
| --- | --- |
| **Signature** | `tooltip:ClearPadding()` |
| **Available on** | `GameTooltip` |
| **Doc** | Used in `SharedTooltipTemplates.lua` — undocumented C++ |
| **Currently used?** | ❌ Never used in TacoTip |

Resets padding to defaults. Pair with `SetPadding` if we ever touch padding.

---

## 5. Clamping

### `tooltip:SetClampRectInsets(left, right, top, bottom)`

| Field | Value |
| --- | --- |
| **Signature** | `tooltip:SetClampRectInsets(left: number, right: number, top: number, bottom: number)` |
| **Available on** | All frame types (inherited from Frame) |
| **Doc** | Undocumented C++ method (used in `SharedTooltip.lua:12`) |
| **Currently used?** | ❌ Never used in TacoTip |
| **Blizzard usage** | `self:SetClampRectInsets(0, 0, 25, 0)` — pushes tooltip up 25px from screen bottom |

**How we could use it:**

Control how close to screen edges the tooltip can go. The default insets vary by client. If we find tooltips clipping off the bottom of the screen, adjusting clamp rect insets would fix it.

---

## 6. Anchor Methods

### `tooltip:GetAnchorType()`

| Field | Value |
| --- | --- |
| **Signature** | `tooltip:GetAnchorType() -> string or nil` |
| **Available on** | `GameTooltip` |
| **Doc** | Undocumented C++ method (used in `GameTooltip.lua` compare-item anchor logic) |
| **Currently used?** | ❌ Never used in TacoTip |

Returns the anchor type string (e.g. `"ANCHOR_LEFT"`, `"ANCHOR_RIGHT"`, `"ANCHOR_NONE"`, `"ANCHOR_PRESERVE"`).

### `tooltip:SetAnchorType(anchorType, xOffset, yOffset)`

| Field | Value |
| --- | --- |
| **Signature** | `tooltip:SetAnchorType(anchorType: string, xOffset: number, yOffset: number)` |
| **Available on** | `GameTooltip` |
| **Doc** | Undocumented C++ method (used in `GameTooltip.lua` compare-item logic) |
| **Currently used?** | ❌ Never used in TacoTip |

**How we could use it:**

Used together with `GetAnchorType` to dynamically adjust tooltip position based on available screen space. If we want tooltips to flip sides when they'd go off-screen, this is how Blizzard does it (see `GameTooltip_AnchorComparisonTooltips`).

---

## 7. Comparison / Shopping Tooltips

These are used by Blizzard's item comparison system. TacoTip already calls `GameTooltip` item tooltips through hooking, but these methods are on the shopping tooltip child frames, not `GameTooltip` itself. Not directly useful unless we build custom item comparison:

- `tooltip:AdvanceSecondaryCompareItem()` — cycle to next comparison item
- `tooltip:ResetSecondaryCompareItem()` — reset comparison state
- `tooltip:IsEquippedItem()` — check if tooltip's item is currently equipped
- `tooltip:SetItemByID(itemID)` — populate tooltip from item ID
- `tooltip:SetQuestLogItem(...)` — populate from quest log
- `tooltip:SetCurrencyByID(currencyID, quantity)` — populate from currency

These exist on `ShoppingTooltip1` / `ShoppingTooltip2`, not on `GameTooltip` itself. Not urgent for this addon.

---

## 8. Miscellaneous

### `tooltip:UpdateTooltip()`

| Field | Value |
| --- | --- |
| **Signature** | `tooltip:UpdateTooltip()` |
| **Available on** | `GameTooltip` (if owner has an `UpdateTooltip` method) |
| **Doc** | Used in `GameTooltip.lua:204` — calls `owner:UpdateTooltip()` or `self:UpdateTooltip()` |
| **Currently used?** | ❌ Never used in TacoTip |

Forces the tooltip to re-run its update function. Could be useful if we modify tooltip content and need Blizzard's layout engine to recalculate.

### `tooltip:SetText(text, r, g, b, alpha, wrap)`

| Field | Value |
| --- | --- |
| **Signature** | `tooltip:SetText(text: string, r: number, g: number, b: number, alpha: number, wrap: boolean)` |
| **Available on** | `GameTooltip` |
| **Doc** | `FrameAPITooltipDocumentation.lua` — Environment: All |
| **Currently used?** | ❌ Never used in TacoTip (TacoTip uses `AddLine` instead) |

Sets the title text of the tooltip (the first/header line). `GameTooltip_SetBasicTooltip` shows the pattern. Not directly useful since TacoTip hooks OnTooltipSetUnit which fires after the title is already set.

---

## Migration Priority

| Priority | Method | Why | Effort |
| --- | --- | --- | --- |
| **P1** | `GetLeftLine(n)` | Replaces fragile `_G[...]` pattern, works on any tooltip variant | Low — mechanical find-replace |
| **P2** | `GetOwner()` | Improves bleed-prevention reliability | Low — single check in `clearTooltipVisuals` |
| **P2** | `IsUnit(unit)` | Simplifies guard in `OnTooltipSetUnit` | Low — replaces UnitExists check |
| **P3** | `GetMinimumWidth()` | Read-before-write in `ApplyTooltipAppearance` | Low — one extra call |
| **P3** | `SetPadding()` / `ClearPadding()` | Needed if we ever resize tooltip content | Medium — requires testing |
| **P4** | `SetClampRectInsets()` | Edge-case screen clipping fix | Low — only if bug reported |
| **P4** | `GetAnchorType()` / `SetAnchorType()` | Dynamic position flip | Medium — complex logic |

---

## API Safety Summary

| Method | Classic Era 1.15.9 | TBC Anniversary 2.5.6 | Guard needed |
| --- | --- | --- | --- |
| `GetLeftLine` | ✅ Documented | ✅ Documented | No |
| `GetRightLine` | ✅ Documented | ✅ Documented | No |
| `GetMinimumWidth` | ✅ Documented | ✅ Documented | No |
| `SetMinimumWidth` | ✅ Documented | ✅ Documented | No |
| `SetText` | ✅ Documented | ✅ Documented | No |
| `GetOwner` | ✅ Used by Blizzard | ✅ Used by Blizzard | No |
| `IsUnit` | ✅ Used by Blizzard | ✅ Used by Blizzard | No |
| `GetAnchorType` | ✅ Used by Blizzard | ✅ Used by Blizzard | No |
| `SetAnchorType` | ✅ Used by Blizzard | ✅ Used by Blizzard | No |
| `ClearPadding` | ✅ Used by Blizzard | ✅ Used by Blizzard | No |
| `SetPadding` | ✅ Used by Blizzard | ✅ Used by Blizzard | No |
| `SetClampRectInsets` | ✅ Used by Blizzard | ✅ Used by Blizzard | No |
| `UpdateTooltip` | ✅ Used by Blizzard | ✅ Used by Blizzard | No |
| `SetMaximumWidth` | ❌ Not a GameTooltip method | ❌ Not a GameTooltip method | **Required** |
| `SetMaxWidth` | ❌ Not a GameTooltip method | ❌ Not a GameTooltip method | **Required** |

All undocumented-but-present methods are C++ widget methods verified by actual call sites in Blizzard's own `/home/sam/wow-ui-source/Interface/AddOns/Blizzard_GameTooltip/Classic/GameTooltip.lua` and `/home/sam/wow-ui-source/Interface/AddOns/Blizzard_SharedXML/SharedTooltipTemplates.lua` on the `classic_era` branch.
