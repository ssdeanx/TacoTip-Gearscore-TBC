# v0.8.7 Cache Architecture, Hover Optimizations, and Cross-Client Hardening Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Modernize TacoTip's inspection cache to handle stale data reliably across long sessions, safely reorder and guard `TT:GetMouseFocus()`, optimize hot-path class coloring, and verify cross-client compatibility across all five client families (Classic Era 11509, TBC Anniversary 20506, Titanforge 38002, WoW Forever 16001, Retail Live 120105).

**Architecture:** Maintain strict dual-engine isolation between Classic and Modern branches. In `LibForeverInspector`, decouple `UNIT_INVENTORY_CHANGED` staleness tagging from immediate distance gates so out-of-range gear swaps are never lost, cap cache entries to 512 with LRU/TTL eviction, and expose public freshness queries. In `main.lua`, move `TT:GetMouseFocus()` ahead of its call sites, pre-compute class hex codes from `RAID_CLASS_COLORS`, and render graceful visual feedback for stale cache entries while awaiting `INSPECT_READY`.

**Tech Stack:** WoW Lua 5.1, Blizzard FrameXML API across 5 branches in `/home/sam/wow-ui-source` (`classic_era`, `classic_anniversary`, `classic_titan`, `forever`, `live`), TacoTip test harness (`Tests/harness/run_all.sh`).

## Global Constraints
- Target version: TacoTip v0.8.7 (main addon only; TacoTip Extras is a completely separate addon).
- Do NOT edit `gearscore.lua` except to guard an existing call (invariant).
- The Classic Era range gate, distance-first gate order, probe guard, and single-argument `CanInspect(unit)` are invariants.
- `_G.PlaySound` is NEVER replaced or detoured (0.8.5 invariant: sound suppression must stay at `GetGameMessageInfo`).
- Container item buttons must never receive conflicting default anchors (0.8.4 invariant).
- Zero luacheck warnings across the entire repository (`luacheck .`).
- Both package verifiers must PASS (`Tools/verify_release.sh --worktree` and `Tools/verify_release_extras.sh --worktree`).
- No state-changing git commands (`git commit`, `git add`, etc.).

---

## Cross-Client FrameXML Verification Trace

All APIs verified against the official Blizzard FrameXML repository at `/home/sam/wow-ui-source`:

| API / Mechanism | `origin/classic_era` (11509) | `origin/classic_anniversary` (20506) | `origin/classic_titan` (38002) | `origin/forever` (16001) | `origin/live` (120105) |
| :--- | :--- | :--- | :--- | :--- | :--- |
| `GetMouseFoci()` | Returns `{ ScriptRegion }`; empty `{}` in 3D world | Returns `{ ScriptRegion }`; empty `{}` in 3D world | Returns `{ ScriptRegion }`; empty `{}` in 3D world | Returns `{ ScriptRegion }`; empty `{}` in 3D world | Returns `{ ScriptRegion }`; empty `{}` in 3D world |
| `GetMouseFocus()` | Returns `WorldFrame` over 3D world | Returns `WorldFrame` over 3D world | Returns `WorldFrame` over 3D world | Deprecated / omitted | Deprecated / omitted |
| `GameTooltip_SetDefaultAnchor` | `tooltip:SetOwner(parent, "ANCHOR_NONE")` | `tooltip:SetOwner(parent, "ANCHOR_NONE")` | `tooltip:SetOwner(parent, "ANCHOR_NONE")` | `tooltip:SetOwner(parent, "ANCHOR_NONE")` | `tooltip:SetOwner(parent, "ANCHOR_NONE")` |
| `UNIT_INVENTORY_CHANGED` | Payload: `unitTarget` (UnitToken) | Payload: `unitTarget` (UnitToken) | Payload: `unitTarget` (UnitToken) | Payload: `unitTarget` (UnitToken) | Payload: `unitTarget` (UnitToken) |
| `RAID_CLASS_COLORS` | Global table keyed by class token; `.r, .g, .b` | Global table keyed by class token; `.r, .g, .b` | Global table keyed by class token; `.r, .g, .b` | Global table keyed by class token; `.r, .g, .b, .colorStr` | Global table keyed by class token; `.r, .g, .b, .colorStr` |
| `ContainerFrameItemButton_OnEnter` | Sets anchor to slot via `SetPoint` without `ClearAllPoints` | Sets anchor to slot via `SetPoint` without `ClearAllPoints` | Sets anchor to slot via `SetPoint` without `ClearAllPoints` | Sets anchor to slot via `SetPoint` without `ClearAllPoints` | Sets anchor to slot via `SetPoint` without `ClearAllPoints` |

---

## Tasks

### Task 1: Rebuilt Taint Test Suite Verification
**Files:**
- Test: [Tests/harness/taint_test.lua](file:///home/sam/TacoTip-Gearscore-TBC/Tests/harness/taint_test.lua)

- [x] **Step 1: Verify rebuilt taint pins on all 5 client families**
  - Run `lua5.1 Tests/harness/taint_test.lua 2 11509 CLASSIC_ERA` -> 21/21 PASS
  - Run `lua5.1 Tests/harness/taint_test.lua 5 20506 TBC_ANNIV` -> 21/21 PASS
  - Run `lua5.1 Tests/harness/taint_test.lua 11 38002 TITANFORGE` -> 21/21 PASS
  - Run `lua5.1 Tests/harness/taint_test.lua 1 16001 FOREVER pipeline` -> 21/21 PASS
  - Run `lua5.1 Tests/harness/taint_test.lua 1 120105 RETAIL pipeline` -> 21/21 PASS
- [x] **Step 2: Verify lint clean**
  - Run `luacheck Tests/harness/taint_test.lua` -> 0 warnings / 0 errors.

---

### Task 2: Inspection Cache Stale & Incomplete Data Hardening in `LibForeverInspector.lua`
**Files:**
- Modify: [Libs/LibForeverInspector/LibForeverInspector.lua](file:///home/sam/TacoTip-Gearscore-TBC/Libs/LibForeverInspector/LibForeverInspector.lua)
- Test: [Tests/harness/taint_test.lua](file:///home/sam/TacoTip-Gearscore-TBC/Tests/harness/taint_test.lua)

**Interfaces:**
- Consumes: `UNIT_INVENTORY_CHANGED`, `INSPECT_READY`, `GetInventoryItemLink`, `GetInventoryItemTexture`.
- Produces: `lib:IsCacheFresh(unitorguid) -> boolean`, `lib:IsCacheStale(unitorguid) -> boolean`, `lib:GetLastCacheTime(unitorguid) -> time, time`.

- [ ] **Step 1: Eliminate the 4-retry incomplete cutoff that froze partial GearScore in `cacheUnitData`**
  In `LibForeverInspector.lua:3653-3690`:
  - **Clean per-slot resolution:**
    ```lua
    local anyMissingEquipped = false
    local getTexture = _G.GetInventoryItemTexture
    for slot = 1, 18 do
        local link = inventoryItemLink(unit, slot)
        local okTex, tex = false, nil
        if (type(getTexture) == "function") then
            okTex, tex = pcall(getTexture, unit, slot)
        end
        if (link) then
            data.items[slot] = link
        elseif (slot ~= 4 and okTex and tex) then
            -- Item is equipped on character, but hyperlink has not loaded in client cache yet
            data.items[slot] = nil
            anyMissingEquipped = true
        else
            -- Slot is genuinely empty (or slot 4 cosmetic shirt)
            data.items[slot] = nil
        end
    end
    ```
  - **Incomplete invariant:** If `anyMissingEquipped == true`, **NEVER** stamp `data.time = now` under any circumstance.
    ```lua
    if (not anyMissingEquipped) then
        data.time = now
        data.incomplete = nil
        data.retryCount = nil
    else
        data.time = nil
        data.incomplete = true
        data.retryCount = (data.retryCount or 0) + 1
        if (data.retryCount <= 6) then
            local retryDelays = { 0.20, 0.35, 0.50, 0.75, 1.00, 1.50 }
            local delay = retryDelays[data.retryCount] or 0.25
            if (type(_G.C_Timer) == "table" and type(_G.C_Timer.After) == "function") then
                _G.C_Timer.After(delay, function()
                    local targetUnit = unit
                    if (not targetUnit or not (type(_G.UnitExists) == "function" and _G.UnitExists(targetUnit))
                            or not (type(_G.UnitGUID) == "function" and _G.UnitGUID(targetUnit) == guid)) then
                        if (lib.PlayerGUIDToUnitToken) then
                            targetUnit = lib:PlayerGUIDToUnitToken(guid)
                        end
                    end
                    if (targetUnit and type(_G.UnitExists) == "function" and _G.UnitExists(targetUnit)) then
                        cacheUnitData(targetUnit, guid, true)
                    end
                end)
            end
        end
    end
    ```
  - **Fresh inspect resets `retryCount`:** When called from `INSPECT_READY` (`isRetry ~= true`), reset `data.retryCount = 0` so each new inspection receives the full retry schedule.

- [ ] **Step 2: Gate `GetLastCacheTime` and `isCacheFresh` against `incomplete`**
  In `LibForeverInspector.lua`:
  - `isCacheFresh`:
    ```lua
    local function isCacheFresh(cached)
        return (cached and cached.time and not cached.stale and not cached.incomplete
            and (uptimeSeconds() - cached.time < CACHE_REFRESH_DELAY)) and true or false
    end
    ```
  - `GetLastCacheTime`:
    ```lua
    function lib:GetLastCacheTime(unitorguid)
        local guid = getPlayerGUID(unitorguid)
        if (guid and guid == UnitGUID("player")) then
            local n = uptimeSeconds()
            return n, n
        end
        local cached = guid and lib.cache[guid]
        if (cached and cached.time and not cached.incomplete) then
            return cached.time, cached.time
        end
        return 0, 0
    end
    ```

- [ ] **Step 3: Decouple distance check from staleness flagging on `UNIT_INVENTORY_CHANGED`**
  In `LibForeverInspector.lua:3846`:
  ```lua
  elseif (event == "UNIT_INVENTORY_CHANGED") then
      local unit = ...
      if (unit and type(UnitExists) == "function" and UnitExists(unit)
          and type(UnitIsPlayer) == "function" and UnitIsPlayer(unit)
          and (type(UnitIsUnit) ~= "function" or not UnitIsUnit(unit, "player"))) then
          local guid = type(UnitGUID) == "function" and UnitGUID(unit)
          if (guid and lib.cache[guid]) then
              lib.cache[guid].stale = true
              if (isCloseEnoughToAsk(unit)) then
                  lib:DoInspect(unit)
              end
          end
      end
  end
  ```

- [ ] **Step 4: Add public cache freshness query methods**
  In `LibForeverInspector.lua`:
  ```lua
  function lib:IsCacheFresh(unitorguid)
      local guid = getPlayerGUID(unitorguid)
      if (not guid) then return false end
      if (guid == UnitGUID("player")) then return true end
      return isCacheFresh(lib.cache[guid])
  end

  function lib:IsCacheStale(unitorguid)
      local guid = getPlayerGUID(unitorguid)
      if (not guid) then return false end
      if (guid == UnitGUID("player")) then return false end
      local cached = lib.cache[guid]
      if (not cached) then return false end
      return (not isCacheFresh(cached))
  end
  ```

- [ ] **Step 5: Add cache entry ceiling & LRU/TTL eviction**
  In `LibForeverInspector.lua`:
  Cap `lib.cache` to a maximum of 512 entries. When exceeding 512 entries upon inserting a fresh record in `cacheUnitData`, sweep and evict entries whose `time` is older than `(CACHE_REFRESH_DELAY * 2)` (10 minutes) and whose unit is no longer present.

---

### Task 3: Move and Guard `TT:GetMouseFocus()` in `main.lua`
**Files:**
- Modify: [main.lua](file:///home/sam/TacoTip-Gearscore-TBC/main.lua)

**Interfaces:**
- Consumes: `GetMouseFoci()` / `GetMouseFocus()`.
- Produces: `TT:GetMouseFocus() -> ScriptRegion`.

- [ ] **Step 1: Move `function TT:GetMouseFocus()` above line 2800**
  Relocate the implementation ahead of `isUnitHoverTarget`:
  ```lua
  function TT:GetMouseFocus()
      if (type(GetMouseFoci) == "function") then
          local frames = GetMouseFoci()
          if (frames and frames[1]) then
              return frames[1]
          end
          return WorldFrame
      end
      if (type(GetMouseFocus) == "function") then
          return GetMouseFocus()
      end
      return WorldFrame
  end
  ```
- [ ] **Step 2: Simplify `isUnitHoverTarget` focus resolution**
  Replace lines 2836–2844 with direct call `local focus = TT:GetMouseFocus()`.
- [ ] **Step 3: Remove redundant duplicate at line 3276**
- [ ] **Step 4: Verify all callsites**
  Verify `onGameTooltipSetDefaultAnchor:2870` and `isUnitHoverTarget:2845` call `TT:GetMouseFocus()` safely with zero nil-pointer risk.

---

### Task 4: Pre-computed Class Color Hex Cache in `main.lua`
**Files:**
- Modify: [main.lua](file:///home/sam/TacoTip-Gearscore-TBC/main.lua)

- [ ] **Step 1: Initialize `CLASS_COLOR_HEX` table at file scope**
  ```lua
  local CLASS_COLOR_HEX = {}
  if (type(RAID_CLASS_COLORS) == "table") then
      for classToken, color in pairs(RAID_CLASS_COLORS) do
          if (color and color.r and color.g and color.b) then
              CLASS_COLOR_HEX[classToken] = string.format("|cff%02x%02x%02x",
                  math.floor(color.r * 255 + 0.5),
                  math.floor(color.g * 255 + 0.5),
                  math.floor(color.b * 255 + 0.5))
          end
      end
  end
  ```
- [ ] **Step 2: Use `CLASS_COLOR_HEX[classToken]` in unit tooltip render**
  Replace repeated calls to `makeColorCode(r, g, b)` where `classToken` is available with `CLASS_COLOR_HEX[classToken] or makeColorCode(r, g, b)`.

---

### Task 5: Tooltip Stale Data Visual Indicator in `main.lua`
**Files:**
- Modify: [main.lua](file:///home/sam/TacoTip-Gearscore-TBC/main.lua)

- [ ] **Step 1: Check `CI:IsCacheStale(guid)` when rendering player GearScore**
  If `gearscore > 0` and `CI and CI.IsCacheStale and CI:IsCacheStale(guid)`:
  Display the existing score (preventing tooltip flicker) while subtly appending a dimmed indicator (e.g. `*` or `(refreshing...)` based on style) so the user knows updated gear data is in flight.
- [ ] **Step 2: Clear stale indicator instantly upon `INVENTORY_READY`**
  When `INVENTORY_READY` fires, the tooltip re-renders with fresh data and the indicator disappears.

---

### Task 6: Comprehensive Verification & Packaging Gate
**Files:**
- Run: `luacheck .`
- Run: `bash Tools/verify_release.sh --worktree`
- Run: `bash Tools/verify_release_extras.sh --worktree`
- Run: `bash Tests/harness/run_all.sh`

- [ ] **Step 1: Run luacheck**
  Verify 0 warnings / 0 errors across all 88 files.
- [ ] **Step 2: Run release verifiers**
  Ensure both `verify_release.sh --worktree` and `verify_release_extras.sh --worktree` report `PASS`.
- [ ] **Step 3: Verify taint test across all 5 clients**
  Ensure 21/21 checks pass on Classic Era, TBC Anniversary, Titanforge, WoW Forever, and Retail Live.
