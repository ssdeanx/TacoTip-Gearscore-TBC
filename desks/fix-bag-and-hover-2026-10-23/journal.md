# Desk: fix-bag-and-hover-2026-10-23 — Journal

## 2026-10-23 — Desk opened

- **Objective:** Fix two specific in-game issues on the reset-back base:
  1. Bag item hover: hovering over an item in bags does not show the tooltip (hovering the bag container itself works).
  2. First hover over a player in TBC Anniversary / Classic Era: partial/incomplete inspect scoring (e.g. GS 104 / partial scan) and ensure clean refresh.
- **Constraints:**
  - DO NOT touch talent rendering (dual spec dimming is intentional and works in TBC / Classic Era SoD).
  - DO NOT break or stretch the tooltip's saved custom position (`custom_pos`).
  - Keep the fix clean, minimal, cross-client compatible, and verified.

## 2026-10-23 — Root Causes & Fixes Landed

### 1. Bag Item Tooltip Vanishing / Anchor Conflict

- **Mechanism:** When hovering a bag item (`ContainerFrameItemButton_OnEnter`), Blizzard calls `GameTooltip:SetOwner(self, "ANCHOR_NONE")`, which triggers `GameTooltipMixin:OnTooltipSetDefaultAnchor() -> GameTooltip_SetDefaultAnchor(self, UIParent)`.
- In TacoTip, `onGameTooltipSetDefaultAnchor` hooked this unconditionally, executing `tooltip:ClearAllPoints()` and `tooltip:SetPoint(anchorPoint, TacoTipDragButton, anchorPoint)`.
- Immediately following that, Blizzard's `ContainerFrameItemButton_CalculateItemTooltipAnchors(self, GameTooltip)` executed `mainTooltip:SetPoint("BOTTOMLEFT"|"BOTTOMRIGHT", self, ...)`. Because Blizzard does not call `ClearAllPoints()`, `GameTooltip` was pinned to BOTH `TacoTipDragButton` and the bag slot button simultaneously, causing the tooltip to stretch across the screen or collapse off-screen (invisible).
- **Fix (`main.lua`):** Added `isUnitHoverTarget(tooltip, parent)` check inside `onGameTooltipSetDefaultAnchor`. If the target is not a unit hover (neither a unit frame with `.unit` nor a 3D world mouseover where `focus == WorldFrame` and `UnitExists("mouseover")`), `onGameTooltipSetDefaultAnchor` exits immediately without mutating points. Bag items retain Blizzard's single clean anchor to the bag slot button. Unit tooltips remain anchored to `TacoTipDragButton` at `custom_pos` without interference.
- **Cross-client audit:**
  - Classic Era, TBC Anniversary, Titanforge: `focus == WorldFrame and UnitExists("mouseover")` handles 3D world unit hover; `parent.unit` and `tooltip.GetUnit` handle unit frame hover; container buttons safely exit.
  - Retail & Forever: `GetMouseFoci()[1] == WorldFrame` and `tooltip:IsTooltipType(Enum.TooltipDataType.Unit)` guard modern tooltips; container buttons safely exit.

### 2. First Hover Player Inspect / Partial Score (GS 104)

- **Mechanism:** When `INSPECT_READY` arrives for a player in Classic/TBC, `cacheUnitData(unit, guid)` in `LibForeverInspector.lua` looped 1 to 18 reading `inventoryItemLink(unit, slot)`. If item links were not yet cached locally in the game client, `GetInventoryItemLink` returned `nil` for those slots, while `GetInventoryItemTexture(unit, slot)` was non-nil (the player was wearing items).
- Previously, `cacheUnitData` wrote `nil` into `data.items[slot]`, set `data.time = now`, and fired `INVENTORY_READY`. `GearScore:GetScore` treated nil slots as unequipped, scored only the 1 or 2 items with links (e.g. GS 104, iLvl 94 for 1 item), and because `data.time` was fresh, the unit was never re-inspected for 5 minutes.
- **Fix (`LibForeverInspector.lua`):** In `cacheUnitData`:
  1. Preserves existing non-nil links in `data.items[slot]`.
  2. Checks `GetInventoryItemTexture(unit, slot)`. If a slot has an item texture but no link yet, marks `incomplete = true`.
  3. If `incomplete`, does not mark `data.time = now` (so `CI:GetLastCacheTime(guid)` returns 0 and `gearscore.lua` does not prematurely show a bogus partial score), and schedules a 250ms retry (`C_Timer.After`) to re-query `cacheUnitData` as soon as the item links arrive from the server.
  4. The retry callback resolves the unit token by GUID via `PlayerGUIDToUnitToken(guid)` if the mouse moved away or the unit was re-targeted.
  5. Once all links are present, `data.time = now`, `INVENTORY_READY` fires, and `GameTooltip:SetUnit` updates with the complete, accurate GearScore.
- **Cross-client audit:**
  - `GetInventoryItemTexture(unit, slot)` exists on all 5 clients (verified against `/home/sam/wow-ui-source` on `classic_era`, `classic_anniversary`, `classic_titan`, `forever`, and `live`).
  - `C_Timer.After` is supported on all 5 clients.

### 3. Invariants & Style

- Talents untouched (dual spec display and active/inactive dimming intact).
- `gearscore.lua` untouched.
- `custom_pos` geometry and mover drag-save untouched.
- Luacheck: 0 warnings / 0 errors across 88 files.
- Verify release scripts: PASS on both TacoTip and TacoTip_Extras.

### 5. Classic Era GameMenu Exit / Logout Button Taint Fix (v0.8.5)

- **Mechanism:** In Classic Era (`isClassic == true`), `installInspectErrorSuppressor()` in `LibForeverInspector.lua` previously installed a detour on `_G.PlaySound`:
  `inspectPlaySound = Detours:DetourHook(lib, "PlaySound", inspectSoundSink)`.
  When the player opens the Game Menu (`GameMenuFrame`) and clicks "Exit Game" or "Logout", Blizzard's button callback calls:

  ```lua
  PlaySound(customSoundEffect or SOUNDKIT.IG_MAINMENU_OPTION)
  HideUIPanel(self)
  callback() -- Protected call to Quit() or Logout()!
  ```

  Because `_G.PlaySound` was replaced with an addon function, the execution call stack became tainted. Two lines later, when Blizzard invoked `Quit()` / `Logout()`, the WoW engine rejected the protected call with `[ADDON_ACTION_FORBIDDEN] AddOn 'TacoTip' tried to call the protected function 'UNKNOWN()'`. As a result, the exit button was blocked on Classic Era.
- **Why it only happened on Classic Era:**
  `installInspectErrorSuppressor` is gated by `if (not isClassic) then return false end`. On TBC Anniversary (`WOW_PROJECT_BURNING_CRUSADE_CLASSIC`), `isClassic` is false, so `PlaySound` was never detoured and the button worked. On Classic Era (`WOW_PROJECT_CLASSIC`), `isClassic` was true, detouring `PlaySound`.
- **Fix (`LibForeverInspector.lua`):**
  1. Removed the detour on `_G.PlaySound` entirely. `_G.PlaySound` remains the clean, untainted Blizzard global on all clients.
  2. Muted the inspect out-of-range sound at `GetGameMessageInfo` instead. When a refusal occurs, `UIErrorsMixin:TryDisplayMessage` calls `local errorStringId, soundKitID, voiceID = GetGameMessageInfo(messageType)` right before playing the sound kit.
  3. Installed `inspectGameMessageInfoSink` via `Detours:DetourHook(lib, "GetGameMessageInfo", inspectGameMessageInfoSink)`. When `swallowedSoundKitID` is armed, it returns `errorName, nil, voiceID`.
  4. Because `soundKitID` returns as `nil`, `UIErrorsFrame` skips calling `PlaySound`, completely suppressing the repetitive out-of-range error sound spam.
  5. Only out-of-range errors (`INSPECT_RANGE_ERROR_NAME == "ERR_OUT_OF_RANGE"`) arm `swallowedSoundKitID`; other refusals remain audible.
  6. Updated `main.lua` and `options.lua` `instant_fade` to use `Detours:SecureHook` rather than `Detours:DetourHook` so `GameTooltip.FadeOut` is never replaced with an addon detour.
### 6. Creature/Target Tooltip Anchoring & TBC World Focus Fix (v0.8.6)

- **Mechanism:** In `v0.8.4`/`v0.8.5`, `isUnitHoverTarget` was introduced to prevent bag slot items from inheriting TacoTip's default anchor hook (`onGameTooltipSetDefaultAnchor`). However, when targeting or hovering creatures in the 3D world on TBC Anniversary / modern client engines:
  1. `GetMouseFoci()` returns an empty table `{}` for 3D world space (so `TT:GetMouseFocus()` returned `nil` instead of `WorldFrame`).
  2. `tooltip:GetUnit()` is not yet populated when `GameTooltip_SetDefaultAnchor` runs.
  3. Consequently, `isUnitHoverTarget` returned `false`, causing `onGameTooltipSetDefaultAnchor` to abort early and leave creature/target tooltips stranded at Blizzard's default screen corner instead of docking to `TacoTipDragButton` (`custom_pos`).
- **Fix:**
  1. Replaced `isUnitHoverTarget` with `isContainerItemButton(frame)` in `main.lua`. It strictly excludes bag and bank container item buttons (which have their own dedicated anchor calculation) while allowing all creatures, targets, players, NPCs, and unit frames to anchor to `TacoTipDragButton` at `custom_pos`.
  2. Updated `TT:GetMouseFocus()` so that when `GetMouseFoci()` returns an empty list, it returns `WorldFrame`.
- **Version Bump:**
  - `TacoTip.toc`: `## Version: 0.8.6`
  - `main.lua`: `addOnVersion` fallback to `"0.8.6"`
  - `options.lua`: `addOnVersion` fallback to `"0.8.6"`
  - `README.md`: `version: 0.8.6`
  - `CHANGELOG.md`: Added `0.8.6` table entry and release notes.
