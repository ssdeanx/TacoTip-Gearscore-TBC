# Design — v0.5.3

## Summary
Six features across three categories for the next release: (1) UI polish — real-time mover, 3→3 page consolidation, (2) new options — NPC classification, creature type, fade delay, tooltip scale, mouse X/Y offsets, item ID/sell price, (3) experimental — opt-in 3D portrait via PlayerModel.

---

## Feature A: Real-Time Mover Follow

### Architecture
- **File:** `main.lua`
- **Change location:** `TacoTipDragButton` script handlers (lines ~1524, ~1457)
- **Pattern:** Same `OnUpdate`-during-drag pattern already used by `CreateMover` (line 1101-1130)

### UI Flow
1. User grabs green mover button → `OnDragStart` fires
2. `self:StartMoving()` moves the button with cursor
3. `OnUpdate` script is set: every frame, calls `GameTooltip:ClearAllPoints()` + `GameTooltip:SetPoint(anchor, TacoTipDragButton, anchor)`
4. Tooltip slides with the button in real-time
5. User releases → `OnDragStop` fires
6. `self:SetScript("OnUpdate", nil)` clears the per-frame binding
7. Existing save/sync flow runs (`syncTooltipMoverPosition(true)`, `refreshOptionsUI()`)

### Why NOT call GameTooltip_SetDefaultAnchor in OnUpdate
- `SetOwner()` + hook re-fire is heavier than just re-pointing
- Risk of Blizzard internal state reset per frame

---

## Feature B: Settings UI Consolidation (4 pages → 3)

### Target Layout

| New Page | Originates From | Contents |
|----------|----------------|----------|
| **General** | Root (pruned) | Status summary, Quick Actions (Mover + Reset), Language dropdown, Tooltip Style dropdown (moved from Root, deduplicated — only one copy), all behavioral toggles (Hide in Combat, Instant Fade → Fade Delay, Enhanced Tooltips, Chat Class Colors, Achievement Points) |
| **Tooltips** | Tooltips (unchanged) | All unit/item content checkboxes, all appearance controls (backdrop, border, portrait, text, bars), live preview pane |
| **Overlays & Positioning** | Positioning + Character & Inspect | All anchor/positioning controls (custom pos, mouse anchor, world/spell anchors, anchor dropdown, mover button, mouse X/Y offsets, tooltip scale), all character/inspect overlay toggles + offset sliders |

### Why 3 pages instead of 2
- Character/inspect offset controls (8 edit boxes + 8 sliders) are visually dense and would overwhelm a combined page
- Behavioral toggles on General give users a "first stop" page before diving into content/appearance

### Files
- `options.lua`: `buildRootPage()` → rename to `buildGeneralPage()`, remove redundant `tip_style`; `buildPositioningPage()` + `buildCharacterInspectPage()` → merge into `buildOverlaysAndPositioningPage()`
- `Locale/enUS.lua`: New page title string for "Overlays & Positioning"

---

## Feature C: Opt-in 3D Portrait

### Architecture
- **File:** `main.lua`, `ensureTooltipPortrait()` function (line ~472)
- **Config:** `TacoTipConfig.tooltip_portrait_3d` (bool, default false)

### UI Flow
1. In `ApplyTooltipAppearance`, after creating the portrait texture (current path)
2. If `tooltip_portrait_3d` is true AND `unit` is valid:
   - Create a `PlayerModel` frame instead of a `Texture`
   - Call `model:SetUnit(unit)` + `model:SetPortraitZoom(1)`
   - Position/size using same portrait scale settings
   - Show/hide with same logic
3. If `tooltip_portrait_3d` is false: use existing `SetPortraitTexture(portrait, unit)` path
4. If `PlayerModel` API not available or errors: fall back silently to 2D path

### Risks
- `PlayerModel:SetUnit()` on a tooltip frame strata may cause rendering order issues
- 3D model at 36px is visually marginal — user must opt in
- Model frame within tooltip may receive mouse events and interfere with tooltip hover

---

## Feature D: Quick-Win Tooltip Enhancements

### D.1 NPC Classification

**File:** `main.lua`, `onTooltipSetUnit` (around level line rendering, ~line 650-700)

Pattern:
```lua
local classification = UnitClassification(unit)
if (classification and classification ~= "normal" and classification ~= "worldboss") then
    local classPrefix = {
        rare = "|cff0070dd+Rare|r ",
        rareelite = "|cff0070dd++Rare Elite|r ",
        elite = "|cffa335ee++Elite|r ",
    }
    -- Prepend to level line text
end
```

**Config key:** `show_classification` (bool, default true)

### D.2 X/Y Mouse Offset Sliders

**File:** `options.lua` (Positioning section), `main.lua` (`CreateMouseAnchor`)

**Config keys:** `anchor_mouse_offset_x` (int, default 0, range -200 to 200), `anchor_mouse_offset_y` (int, default 0, range -200 to 200)

In `CreateMouseAnchor()`, apply offsets:
```lua
local ox = TacoTipConfig.anchor_mouse_offset_x or 0
local oy = TacoTipConfig.anchor_mouse_offset_y or 0
tooltip:ClearAllPoints()
tooltip:SetPoint("ANCHOR_CURSOR", x + ox, y + oy)
```

### D.3 Fade Delay Slider

**File:** `main.lua` (event handler, `instant_fade` section), `options.lua` (Positioning → behavior section)

**Config key:** `fade_delay` (number, default 0, range 0-2.0)

Replace binary `instant_fade` behavior:
```lua
if (TacoTipConfig.fade_delay and TacoTipConfig.fade_delay > 0) then
    GameTooltip:SetFadeDuration(TacoTipConfig.fade_delay)
end
```

### D.4 Creature Type

**File:** `main.lua`, `onTooltipSetUnit`

Added as optional line after level:
```lua
if (TacoTipConfig.show_creature_type and not UnitIsPlayer(unit)) then
    local creatureType = UnitCreatureType(unit)
    if (creatureType) then
        -- Add line: "Humanoid" / "Beast" / etc
    end
end
```

### D.5 Item Sell Price

**File:** `main.lua`, `itemToolTipHook` (~line 943)

```lua
local _, itemLink = self:GetItem()
if (itemLink and TacoTipConfig.show_sell_price) then
    local price = select(11, GetItemInfo(itemLink))
    if (price and price > 0) then
        local totalPrice = price * (select(2, GetItemCount(itemLink)) or 1)
        self:AddLine("Sell Price: " .. GetCoinText(totalPrice), 1, 1, 0)
    end
end
```

### D.6 Item ID

**File:** `main.lua`, `itemToolTipHook`

```lua
local itemID = GetItemInfoFromHyperlink(itemLink) or itemLink:match("item:(%d+)")
if (itemID) then
    self:AddLine("Item ID: " .. itemID, 0.5, 0.5, 0.5)
end
```

### D.7 Tooltip Scale

**File:** `options.lua` (Positioning section) + `main.lua` (ApplyTooltipAppearance)

**Config key:** `tooltip_scale` (number, default 1.0, range 0.5-1.5)

Apply in `ApplyTooltipAppearance`:
```lua
tooltip:SetScale(TacoTipConfig.tooltip_scale or 1)
```

---

## Data Structures

### New Config Keys (in `options.lua` defaults)
```lua
show_classification = true,               -- NPC Elite/Rare/Boss markers
anchor_mouse_offset_x = 0,               -- Mouse anchor X offset
anchor_mouse_offset_y = 0,               -- Mouse anchor Y offset
fade_delay = 0,                          -- Tooltip fade delay (0 = instant)
show_creature_type = true,               -- Show creature type on non-player units
show_sell_price = true,                   -- Show item sell price in tooltips
show_item_id = false,                     -- Show item ID in tooltips
tooltip_scale = 1.0,                      -- Tooltip scale multiplier
tooltip_portrait_3d = false,              -- Use 3D PlayerModel portrait
```

### Locale Strings (add to `Locale/enUS.lua`)
```lua
["OPTIONS_SHOW_CLASSIFICATION"] = "Show NPC classification"
["OPTIONS_SHOW_CLASSIFICATION_DESC"] = "Display Elite, Rare, and Boss markers on NPC tooltips."
["OPTIONS_ANCHOR_MOUSE_OFFSET_X"] = "Mouse anchor X offset"
["OPTIONS_ANCHOR_MOUSE_OFFSET_Y"] = "Mouse anchor Y offset"
["OPTIONS_FADE_DELAY"] = "Fade delay"
["OPTIONS_FADE_DELAY_DESC"] = "Delay before tooltip fades out. Set to 0 for instant fade."
["OPTIONS_SHOW_CREATURE_TYPE"] = "Show creature type"
["OPTIONS_SHOW_CREATURE_TYPE_DESC"] = "Display creature type (Humanoid, Beast, etc) on NPC tooltips."
["OPTIONS_SHOW_SELL_PRICE"] = "Show sell price"
["OPTIONS_SHOW_SELL_PRICE_DESC"] = "Display vendor sell price on item tooltips."
["OPTIONS_SHOW_ITEM_ID"] = "Show item ID"
["OPTIONS_SHOW_ITEM_ID_DESC"] = "Display item ID on item tooltips for Wowhead lookups."
["OPTIONS_TOOLTIP_SCALE"] = "Tooltip scale"
["OPTIONS_TOOLTIP_SCALE_DESC"] = "Scale the entire tooltip up or down."
["OPTIONS_PORTRAIT_3D"] = "Show 3D portrait"
["OPTIONS_PORTRAIT_3D_DESC"] = "Use live 3D player model instead of 2D portrait icon."
["OPTIONS_SECTION_OVERLAYS_AND_POSITIONING"] = "Positioning & Overlays"
```

## Risks
1. Feature A: `SetPoint()` every frame during drag may cause FPS impact on low-end machines — verify on 2.5.5
2. Feature C: `PlayerModel` embedded in tooltip may intercept mouse clicks — set `model:EnableMouse(false)` and `model:SetFrameLevel()` below text
3. Feature B: Merging anchor_mouse_world toggle into different page may confuse users who were used to Positioning page layout
4. Feature D.5: `GetItemInfo(link)` may return nil for uncached items — gate with `GetItemInfoInstant` or defer via async callback

## Verification
1. Test mover drag on 2.5.5 with both custom_pos and anchor_mouse modes active
2. Test options page navigation — all controls accessible in new 3-page layout
3. Test 3D portrait on player, NPC, and pet units — verify graceful fallback
4. Test NPC classification on elite, rare, rareelite, boss, and normal mobs
5. Test item ID/sell price with cached and uncached items
6. Run targeted diagnostics on `main.lua` and `options.lua` after changes
