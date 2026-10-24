# Desk: cache-and-hover-optimizations-v087 — Journal

## 2026-10-24 — Desk Opened

- **Objective:**
  1. Deep audit and modernization of TacoTip's inspection cache in `LibForeverInspector.lua` to handle stale data reliably across long game sessions.
  2. Safety audit and reordering of `TT:GetMouseFocus()` in `main.lua` to eliminate forward-reference and nil-call risks.
  3. Rebuild and update `Tests/harness/taint_test.lua` so it accurately validates the current v0.8.6/v0.8.7 architecture across all five client families (Classic Era, TBC Anniversary, Titanforge, WoW Forever, Retail Live).
  4. Formulate verified optimizations (pre-computed class color hex cache, comparison tooltip delta, adaptive raid scan throttle) while leaving `gearscore.lua` and repo invariants untouched.

- **Constraints:**
  - Focus strictly on the main addon (`TacoTip`); `TacoTip_Extras` is a completely separate addon.
  - Strict preservation of the invariants in `workshop.md`:
    - No state-changing git commands (`git commit`, `git add`).
    - `gearscore.lua` formula and internals are untouched.
    - Classic Era distance-first gate order and single-argument `CanInspect(unit)` are untouched.
    - `_G.PlaySound` is NEVER hooked or detoured.
    - Container item buttons must bypass default re-anchoring to avoid dual-anchor stretch.
  - Zero luacheck warnings (`luacheck .`).
  - Both release package verifiers must PASS (`Tools/verify_release.sh --worktree` and `Tools/verify_release_extras.sh --worktree`).

---

## 2026-10-24 — Cross-Client FrameXML Audit (/home/sam/wow-ui-source)

All claims verified directly against the official Blizzard FrameXML repository across all five branch heads:

### 1. `GetMouseFoci` vs. `GetMouseFocus`
- **`origin/classic_era`**, **`origin/classic_anniversary`**, **`origin/classic_titan`**:
  `GetMouseFocus()` exists in FrameXML (`SharedUIPanelTemplates.lua:1601`). `GetMouseFoci()` also exists in modern 1.15.x / 2.5.x engine builds (`InputDocumentation.lua:30`).
- **`origin/forever`**, **`origin/live`**:
  `GetMouseFoci()` is the primary modern API (`InputDocumentation.lua:54`). `GetMouseFocus()` is deprecated or absent.
- **Engine Behavior in 3D World Space:**
  When the mouse cursor is over the 3D world (not over any UI frame or button), `GetMouseFoci()` returns an empty table `{}`.
  TacoTip's `TT:GetMouseFocus()` safely falls back to returning `WorldFrame` when `GetMouseFoci()` returns an empty table, matching the classic contract and allowing 3D world unit mouseover detection to succeed.

### 2. `GameTooltip_SetDefaultAnchor` & Bag Container Buttons
- **`origin/classic_era`**, **`origin/classic_anniversary`**, **`origin/classic_titan`**, **`origin/forever`**, **`origin/live`**:
  `GameTooltip_SetDefaultAnchor(tooltip, parent)` calls `tooltip:SetOwner(parent, "ANCHOR_NONE")`.
  When hovering 3D world units, Blizzard passes `parent = UIParent`.
  When hovering container items in bags, Blizzard calls `ContainerFrameItemButton_OnEnter`, invoking `GameTooltip:SetOwner(self, "ANCHOR_NONE")` followed immediately by `ContainerFrameItemButton_CalculateItemTooltipAnchors(self, GameTooltip)`.
  Because `ContainerFrameItemButton_CalculateItemTooltipAnchors` attaches `BOTTOMLEFT` or `BOTTOMRIGHT` to the container item button *without calling `ClearAllPoints()`*, gating `onGameTooltipSetDefaultAnchor` behind `isUnitHoverTarget(tooltip, parent)` prevents attaching a conflicting second point to `TacoTipDragButton`, eliminating tooltip stretch.

### 3. `UNIT_INVENTORY_CHANGED` Event Payload
- **`origin/classic_era`** (`UnitDocumentation.lua:2809`), **`origin/classic_anniversary`**, **`origin/classic_titan`**, **`origin/forever`**, **`origin/live`**:
  `UNIT_INVENTORY_CHANGED` passes payload `{ Name = "unitTarget", Type = "UnitTokenVariant" }`.
  When a remote party or raid member changes gear, `UNIT_INVENTORY_CHANGED` fires with their unit token.

---

## 2026-10-24 — Cache Audit & Stale Data Analysis

### Current Flaws Identified in `LibForeverInspector.lua`:
1. **Out-of-Range Gear Swaps ([line 3851](file:///home/sam/TacoTip-Gearscore-TBC/Libs/LibForeverInspector/LibForeverInspector.lua#L3851)):**
   `UNIT_INVENTORY_CHANGED` currently checks `if (... and isCloseEnoughToAsk(unit)) then lib.cache[guid].stale = true ...`.
   If a party or raid member equips gear 30 yards away (outside the ~28yd inspect gate), `isCloseEnoughToAsk` is `false`, so `stale = true` is **never set**. Their cache entry falsely stays marked "fresh" with old gear for up to 300s. Even if they walk right next to you later, hovering them returns cached data without re-inspecting.
   *Fix:* Unconditionally flag `lib.cache[guid].stale = true` for known GUIDs, and only gate the immediate `DoInspect` call behind `isCloseEnoughToAsk(unit)`. If out of range, the stale flag remains set, guaranteeing that the next time they are hovered/targeted in range, fresh inspection triggers immediately.
2. **Unbounded Cache Growth:**
   `lib.cache` accumulates every inspected GUID indefinitely. Over hours in Dalaran or Orgrimmar, thousands of players remain cached.
   *Fix:* Implement a 512-entry ceiling with LRU/TTL eviction for entries older than 10 minutes whose units are no longer present.
3. **Private vs. Public Freshness API:**
   `isCacheFresh` is a private local helper. Callers cannot check whether an entry is fresh or stale.
   *Fix:* Expose `lib:IsCacheFresh(unitorguid)` and `lib:IsCacheStale(unitorguid)`.

---

## 2026-10-24 — Rebuilt Taint Test Results

`Tests/harness/taint_test.lua` was rebuilt to test the actual v0.8.5 and v0.8.6 architecture:
- Pin (a): `instant_fade` uses `SecureHook`, preserving `GameTooltip.FadeOut` identity.
- Pin (b): `GameTooltip_SetDefaultAnchor` post-hook no-ops on menu owners, repositions unit owners.
- Pin (c): `_G.PlaySound` is NEVER replaced or detoured (0.8.5 regression pin).
- Pin (d): `installInspectErrorSuppressor` detours `GetGameMessageInfo` on Classic Era without touching `PlaySound`, and is not installed on non-Classic clients.
- Pin (e): 3D world unit hovers (`parent == UIParent`, `WorldFrame`, or `nil`) dock to custom position (0.8.6).
- Pin (f): Container frame item buttons (`ContainerFrameItemButton*`) pass through without `SetPoint` collisions (0.8.6).
- Pin (g): `TT:GetMouseFocus()` falls back to `WorldFrame` when `GetMouseFoci()` returns `{}` over the 3D world (0.8.6).

### Verification:
```
CLASSIC_ERA  taint pins ok (21 checks)
TBC_ANNIV    taint pins ok (21 checks)
TITANFORGE   taint pins ok (21 checks)
FOREVER      taint pins ok (21 checks)
RETAIL       taint pins ok (21 checks)
```
- `luacheck Tests/harness/taint_test.lua`: 0 warnings / 0 errors.
- `luacheck .`: 0 warnings / 0 errors across all 88 files.
- `Tools/verify_release.sh --worktree`: PASS.
- `Tools/verify_release_extras.sh --worktree`: PASS.

---

## 2026-10-24 — Test Suite Alignment: Removing Extras-Forwarding Checks

Per operator direction:
- Removed obsolete test blocks asserting `/tt` forwarding to `TacoTip_Extras` in:
  - `Tests/harness/gearscore_test.lua` (Section 8: lines 608-759)
  - `Tests/harness/options_test.lua` (lines 973-1077 and 1148-1185)
- Verified `gearscore_test.lua` now passes **ALL 31 checks** across all 5 clients (`CLASSIC_ERA`, `TBC_ANNIV`, `TITANFORGE`, `RETAIL`, `UNKNOWN`) and under `lua5.1`, `lua5.2`, and `luajit`.
- Zero occurrences of `TACOTIPRANKS` or `extrasForwardFailed` remain in `Tests/harness/`.

---

## 2026-10-24 — State Reconciliation & Audit Catch-Up

1. **State of `main.lua`:**
   - Operator rejected speculative edits to `main.lua`.
   - File restored completely to clean production release (4004 lines, 189,218 bytes).
   - Invariant verified: `TT:GetMouseFocus()` is intact at line 3276; `clearTooltipPlayerClassColor` is intact at line 415. No production logic altered.

2. **Inventory Slot Verification (Blizzard FrameXML Truth):**
   - Verified against `origin/classic_era` `/home/sam/wow-ui-source/Interface/AddOns/Blizzard_FrameXMLBase/Classic/Constants.lua:172-192` and web API documentation:
     - Slot 1: Head (`INVSLOT_HEAD`)
     - Slot 2: Neck (`INVSLOT_NECK`)
     - Slot 3: Shoulder (`INVSLOT_SHOULDER`)
     - Slot 4: Shirt (`INVSLOT_BODY`)
     - Slot 5: Chest (`INVSLOT_CHEST`)
     - Slot 19: Tabard (`INVSLOT_TABARD`)
   - Empty slot mechanics verified: `GetInventoryItemTexture(unit, slot)` returns `nil` for empty slots. Therefore, `okTex and tex` evaluates to `false`, and empty slots never trigger `anyMissingEquipped = true` in `LibForeverInspector.lua`.
   - Tabard (slot 19) is outside the 1..18 loop entirely.

3. **Test Suite Status & Plan:**
   - Several suites pass (`gearscore_test.lua`, `taint_test.lua`, `load_test.lua`).
   - Remaining failing suites fail solely because they assert speculative, unmerged features from earlier experimental branches (tri-state inspect `"queued"`, Hunter wait-stats in `detect_test.lua`, fileguard LibStub assert, absent-Pawn table, etc.).
   - Operator directive: comment out tests for unimplemented features with clear notes ("could be implemented or maybe just need change to working code") to bring the harness back in sync with the working codebase.

