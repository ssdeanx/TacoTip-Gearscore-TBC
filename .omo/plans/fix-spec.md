# TacoTip Gearscore TBC — Fix Specification v1.0

> Decision-complete spec for implementing fixes identified in the July 2026 audit.
> Each fix is independently scoped so they can be worked in any order (unless dependencies are noted).

---

## Table of Contents

1. [P1 — tip_style forced to 2 on every load](#p1--tip_style-forced-to-2-on-every-load)
2. [P2 — GetQuality green/blue channel swap](#p2--getquality-greenblue-channel-swap)
3. [P3 — CAfter border bleed via onTooltipShow non-unit branch](#p3--cafter-border-bleed-via-ontooltipshow-non-unit-branch)
4. [P4 — Power bar not cleaned in clearTooltipVisuals](#p4--power-bar-not-cleaned-in-cleartooltipvisuals)
5. [P5 — TacoTipPowerBar mid-tooltip config change gap](#p5--tacotippowerbar-mid-tooltip-config-change-gap)
6. [P6 — Locale gaps (22 missing from non-en, 4 missing from enUS)](#p6--locale-gaps-22-missing-from-non-en-4-missing-from-enus)
7. [P7 — Test suite: custom_pos/custom_anchor assertions fail](#p7--test-suite-custom_poscustom_anchor-assertions-fail)
8. [P8 — PawnGetSingleValueFromItem unprotected call](#p8--pawngetsinglevaluefromitem-unprotected-call)
9. [P9 — GetPlayerInfoByGUID structural fragility](#p9--getplayerinfobyguid-structural-fragility)
10. [P10 — Test: Borders:PlayerGetsClassBorder fragility](#p10--test-bordersplayergetsclassborder-fragility)
11. [P11 — Config key color channels missing range validation](#p11--config-key-color-channels-missing-range-validation)

---

## Priority Legend

| Tag | Meaning |
|-----|---------|
| P1 | **CRITICAL** — breaks user-facing feature for everyone |
| P2–P4 | **HIGH** — visible bug affecting real users |
| P5–P6 | **MEDIUM** — visual/cosmetic, affects subset of users |
| P7–P11 | **LOW** — test issues, edge cases, defense-in-depth |

---

## P1 — tip_style forced to 2 on every load

**Priority**: P1 (CRITICAL)
**Files**: `options.lua`, `TacoTip_Tests.lua`
**Est. effort**: 1 line change + test update

### Problem

`tip_style` (an integer enum 1–5) is listed in the `booleanKeys` table inside `SafeSanitizeConfig`. The boolean sanitizer loop runs **first** and sees that `type(3)` is `"number"` not `"boolean"`, so it resets `config.tip_style` to `defaults.tip_style` (= 2). The numeric range checker at lines 204–206 runs **after** the boolean loop but by then the original value is already overwritten.

**Impact**: Any user who selects `tip_style = 1` (Full), `= 3` (Wide), `= 4` (Hybrid Mini), or `= 5` (Mini) will find it silently reverted to `= 2` (Compact/Hybrid Wide) after every `/reload` or game restart. Only `= 2` survives.

### Root cause

`options.lua` line 165: `"tip_style"` appears in the `booleanKeys` list, but its default is `2` (a number, not boolean).

### Fix

**Step 1**: Remove `"tip_style"` from the `booleanKeys` list.

File: `options.lua`, line ~165. Find:

```lua
    "show_item_level",
    "tip_style", "show_target", "show_pawn_player",
```

Change to:

```lua
    "show_item_level",
    "show_target", "show_pawn_player",
```

The numeric range check at lines 204–206 already handles `tip_style` correctly:
```lua
if (type(config.tip_style) ~= "number" or config.tip_style < 1 or config.tip_style > 5) then
    config.tip_style = defaults.tip_style
end
```
No changes needed to that code.

**Step 2**: Update the test in `TacoTip_Tests.lua`.

The existing `Config:SanitizeBounds` test (lines 87–102) tests that `tip_style = 42` gets clamped, but it passes for the wrong reason (boolean sanitizer clobbers to 2 before numeric check fires). After the fix, add a test case that verifies a **valid** value survives sanitization:

```lua
-- After the existing bounds checks, add:
do
    local cfg2 = TT:GetDefaults()
    cfg2.tip_style = 3
    TT:SafeSanitizeConfig(cfg2)
    IsTrue(cfg2.tip_style == 3, "valid tip_style preserved after sanitize")
end
```

### Verification

1. Open the game, set `/tacotip` → Tooltips → Style = "Full" (tip_style=1)
2. Type `/reload`
3. Open the options panel → verify Style still shows "Full"
4. Repeat for styles 3, 4, 5

---

## P2 — GetQuality green/blue channel swap

**Priority**: P2 (HIGH)
**Files**: `gearscore.lua`
**Est. effort**: 2 line changes

### Problem

In `GetQuality()` (lines 217–219), the variable assignments read from the wrong table keys:

```lua
local Red =   GS_Quality[...].Red["A"] + (...)   -- CORRECT
local Blue =  GS_Quality[...].Green["A"] + (...)  -- BUG: should be .Blue
local Green = GS_Quality[...].Blue["A"] + (...)   -- BUG: should be .Green
```

The `Blue` variable uses the `Green` table's coefficients, and the `Green` variable uses the `Blue` table's coefficients. Only `Red` is correct. This is a copy-paste error where the table key was incremented to the next color instead of matching the variable name.

**Impact**: GearScore tooltip text (consumed at `main.lua:951` as `r, g, b`) displays with inverted green↔blue channels. Intended amber/golden text renders as purple/magenta. The `GS_Quality` data table itself is correct — only the formulas that read it are wrong.

### Root cause

`gearscore.lua` lines 218–219 — the table key name was advanced `.Green` → `.Blue` when the variable name was changed `Red` → `Blue` → `Green`, skipping the correct match.

### Fix

Change line 218: Replace all 4 occurrences of `.Green` with `.Blue`
Change line 219: Replace all 4 occurrences of `.Blue` with `.Green`

Line 218 before:
```lua
local Blue = GS_Quality[( i + 1 ) * BRACKET_SIZE].Green["A"] + (((ItemScore - GS_Quality[( i + 1 ) * BRACKET_SIZE].Green["B"])*GS_Quality[( i + 1 ) * BRACKET_SIZE].Green["C"])*GS_Quality[( i + 1 ) * BRACKET_SIZE].Green["D"])
```

Line 218 after:
```lua
local Blue = GS_Quality[( i + 1 ) * BRACKET_SIZE].Blue["A"] + (((ItemScore - GS_Quality[( i + 1 ) * BRACKET_SIZE].Blue["B"])*GS_Quality[( i + 1 ) * BRACKET_SIZE].Blue["C"])*GS_Quality[( i + 1 ) * BRACKET_SIZE].Blue["D"])
```

Line 219 before:
```lua
local Green = GS_Quality[( i + 1 ) * BRACKET_SIZE].Blue["A"] + (((ItemScore - GS_Quality[( i + 1 ) * BRACKET_SIZE].Blue["B"])*GS_Quality[( i + 1 ) * BRACKET_SIZE].Blue["C"])*GS_Quality[( i + 1 ) * BRACKET_SIZE].Blue["D"])
```

Line 219 after:
```lua
local Green = GS_Quality[( i + 1 ) * BRACKET_SIZE].Green["A"] + (((ItemScore - GS_Quality[( i + 1 ) * BRACKET_SIZE].Green["B"])*GS_Quality[( i + 1 ) * BRACKET_SIZE].Green["C"])*GS_Quality[( i + 1 ) * BRACKET_SIZE].Green["D"])
```

### Verification

1. Hover a player with epic gear (quality bracket 5)
2. GearScore number should display with an appropriate color (purple-ish for epic, not shifted toward incorrect hue)
3. Cross-check by computing: `r` = `.Red` formula, `g` = `.Green` formula, `b` = `.Blue` formula

---

## P3 — CAfter border bleed via onTooltipShow non-unit branch

**Priority**: P2 (HIGH)
**Files**: `main.lua`
**Est. effort**: 1 line change

### Problem

In `onTooltipShow` (lines 1241–1246), when the tooltip shows non-unit content (map icon, UI element, world POI) while `TacoTipPlayerClassColor` is still set from a previous player hover, the function resets the border to default but **does not clear** `TacoTipPlayerClassColor`:

```lua
if (not unit or not UnitIsPlayer(unit)) then
    resetTooltipBorderToDefault(tooltip)
    return  -- <-- leaves TacoTipPlayerClassColor stale on the tooltip
end
```

Any pending `CAfter(0.05)` (from `ApplyTooltipAppearance` line 499) or `CAfter(0)` (from `onTooltipShow` line 1249) was scheduled with `isPlayerTooltip=true` from a previous player hover. When it fires, it sees the stale `TacoTipPlayerClassColor` and re-applies the class-color border to the non-unit tooltip.

**Impact**: Class-colored borders bleed onto minimap icons, world map POIs, UI element tooltips, and spell/buff tooltips — but only during rapid transitions where `OnTooltipCleared` doesn't fire between unit changes (a documented behavior on TBC Anniversary client, noted at lines 1270–1272).

### Root cause

`main.lua` lines 1241–1246: The non-unit branch calls `resetTooltipBorderToDefault` but not `clearTooltipPlayerClassColor`. This leaves the stale cache for any pending CAfter to pick up.

### Fix

Add `clearTooltipPlayerClassColor(tooltip)` before `resetTooltipBorderToDefault(tooltip)` at line 1245.

File: `main.lua`, line ~1241–1246.

Before:
```lua
if (not unit or not UnitIsPlayer(unit)) then
    -- Non-player / non-unit tooltip (items, spells, minimap or world-map
    -- POI icons). Drop any class-colored border left by the previous
    -- player hover so it cannot bleed through onto this tooltip.
    resetTooltipBorderToDefault(tooltip)
    return
end
```

After:
```lua
if (not unit or not UnitIsPlayer(unit)) then
    -- Non-player / non-unit tooltip (items, spells, minimap or world-map
    -- POI icons). Drop any class-colored border left by the previous
    -- player hover so it cannot bleed through onto this tooltip, and clear
    -- the cached class color so no pending CAfter can re-apply it.
    clearTooltipPlayerClassColor(tooltip)
    resetTooltipBorderToDefault(tooltip)
    return
end
```

### Dependencies

None. This is a standalone defensive fix. The `clearTooltipPlayerClassColor` function is already defined at `main.lua:179–183` and is nil-safe (guards `if (tooltip) then`).

### Verification

Testing requires a live WoW client on TBC Anniversary (20505). Steps:
1. Enable `tooltip_border_use_class` (default: on)
2. Hover over a player unit → verify class-colored border appears
3. Rapidly move cursor to a minimap icon (quest, flight point, dungeon entrance) → verify border reverts to default gray, not class color
4. Repeat with `/tacotip` → Tooltips → various `tip_style` values to confirm no regression

---

## P4 — Power bar not cleaned in clearTooltipVisuals

**Priority**: P2 (HIGH)
**Files**: `main.lua`
**Est. effort**: 4 lines added

### Problem

`clearTooltipVisuals()` (lines 642–657) is the centralized cleanup function called by every non-unit handler (OnTooltipCleared, OnTooltipSetItem, OnTooltipSetSpell, onTooltipShow nil-cache path, onTooltipSetUnit stale-unit path). It cleans up:
- `TacoTipPlayerClassColor` → nil
- Border → default color
- 2D portrait → hidden
- 3D portrait → hidden
- Elite frame → hidden

But it does **NOT** touch `TacoTipPowerBar` or its `updateTicker`. This means:

- **OnTooltipSetSpell** path (where `OnTooltipCleared` is not guaranteed to fire): power bar stays visible on spell tooltips
- **OnTooltipSetItem** path: power bar stays visible if `GameTooltipStatusBar:OnHide` doesn't fire
- **OnShow** (non-unit) path: power bar stays visible

The only indirect mechanism that hides the power bar is the `GameTooltipStatusBar:OnHide` hook (line 1376–1382), which is fragile — it doesn't fire during the OnTooltipSetSpell path, and doesn't apply to ShoppingTooltips or ItemRefTooltip.

**Impact**: Stale power bar with outdated data visible on non-unit tooltips. Update ticker continues running.

### Root cause

`clearTooltipVisuals` (main.lua lines 642–657) was designed before the power bar was added and was never updated to include it.

### Fix

Add power bar cleanup to `clearTooltipVisuals`.

File: `main.lua`, lines 642–657. After the elite frame hide, add:

```lua
if (TacoTipPowerBar) then
    TacoTipPowerBar:Hide()
end
stopPowerBarTicker()
```

The function after fix should look like:

```lua
local function clearTooltipVisuals(tooltip)
    if (not tooltip) then
        return
    end
    clearTooltipPlayerClassColor(tooltip)
    resetTooltipBorderToDefault(tooltip)
    if (tooltip.TacoTipPortrait) then
        tooltip.TacoTipPortrait:Hide()
    end
    if (tooltip.TacoTipPortrait3D) then
        tooltip.TacoTipPortrait3D:Hide()
    end
    if (tooltip.TacoTipEliteFrame) then
        tooltip.TacoTipEliteFrame:Hide()
    end
    if (TacoTipPowerBar) then
        TacoTipPowerBar:Hide()
    end
    stopPowerBarTicker()
end
```

### Verification

1. Hover a unit with mana/power (mage, warlock, etc.)
2. Verify power bar appears below tooltip
3. Move cursor to a spell icon → spell tooltip shows without power bar
4. Verify no Lua errors in chat

---

## P5 — TacoTipPowerBar mid-tooltip config change gap

**Priority**: P3 (MEDIUM)
**Files**: `options.lua` (Tooltips page, power bar checkbox callback), possibly `main.lua`
**Est. effort**: 2–5 lines

### Problem

When the user toggles `show_power_bar` via the options UI while a unit tooltip is currently shown, there is no reactive code path that hides/shows the live `TacoTipPowerBar`. The options checkbox callback (options.lua line 1732) writes the config key and calls `modernShowExampleTooltip()` (which only affects the options-preview power bar), but the **live in-game power bar** stays visible (or hidden) in its previous state until the next `OnTooltipSetUnit` event.

The update ticker also continues running if the bar was previously shown.

**Impact**: Config change does not visually apply until the next mouseover. Minor UX issue.

### Root cause

No reactive handler for config key changes to the live power bar. The options UI writes `TacoTipConfig.show_power_bar = value` but doesn't call a live refresh function.

### Fix

In options.lua, near the `show_power_bar` checkbox callback (line 1426–1430 area), after writing the config value and calling `modernShowExampleTooltip()`, also refresh the live tooltip state:

```lua
-- After the checkbox callback writes TacoTipConfig.show_power_bar and calls
-- modernShowExampleTooltip(), add:
if (TT.ApplyTooltipAppearance and GameTooltip:IsShown()) then
    local unit = resolveTooltipUnit(GameTooltip)
    if (unit) then
        TT:ApplyTooltipAppearance(GameTooltip, unit)
    end
end
```

Alternatively, call `TT:RefreshOptionsUI()` which already calls `ensureModernOptionsBuilt` → `modernShowExampleTooltip`. But that won't affect the live tooltip. The cleanest approach is to force a `resolveTooltipUnit` + `ApplyTooltipAppearance` on the live GameTooltip.

---

## P6 — Locale gaps (22 missing from non-en, 4 missing from enUS)

**Priority**: P3 (MEDIUM)
**Files**: `Locale/enUS.lua`, all 10 non-English locale files, `options.lua`
**Est. effort**: ~22 × 10 = 220 line additions (automated)

### Problem

**A) 22 keys missing from every non-English locale file** (all 10: deDE, esES, esMX, frFR, itIT, koKR, ptBR, ruRU, zhCN, zhTW):

1. `["Honor Rank"]`
2. `["OPTIONS_PORTRAIT_ZOOM"]`
3. `["OPTIONS_PORTRAIT_ZOOM_DESC"]`
4. `["OPTIONS_SHOW_GS_DELTA"]`
5. `["OPTIONS_SHOW_GS_DELTA_DESC"]`
6. `["OPTIONS_SHOW_HONOR_RANK"]`
7. `["OPTIONS_SHOW_HONOR_RANK_DESC"]`
8. `["OPTIONS_SHOW_ILVL_INLINE"]`
9. `["OPTIONS_SHOW_ILVL_INLINE_DESC"]`
10. `["OPTIONS_SHOW_REALM"]`
11. `["OPTIONS_SHOW_REALM_DESC"]`
12. `["OPTIONS_SHOW_ROLE_ICON"]`
13. `["OPTIONS_SHOW_ROLE_ICON_DESC"]`
14. `["OPTIONS_SHOW_SEPARATORS"]`
15. `["OPTIONS_SHOW_SEPARATORS_DESC"]`
16. `["OPTIONS_TOOLTIP_BORDER_THICKNESS"]`
17. `["OPTIONS_TOOLTIP_BORDER_THICKNESS_DESC"]`
18. `["OPTIONS_TOOLTIP_DELAY"]`
19. `["OPTIONS_TOOLTIP_DELAY_DESC"]`
20. `["OPTIONS_TOOLTIP_MAX_WIDTH"]`
21. `["OPTIONS_TOOLTIP_MAX_WIDTH_DESC"]`
22. `["Realm"]`

These display in English (via enUS.lua fallback merge) rather than the player's locale.

**B) 4 keys used in code but missing from enUS.lua** (the source-of-truth):

1. `L["REALM"]` — used at `options.lua:1318`. enUS has `["Realm"]` (camelCase) but not `["REALM"]` (all-caps).
2. `L["RANK_TITLE"]` — used at `options.lua:1326`
3. `L["OPTIONS_OFFSET_EDIT_DESC"]` — used at `options.lua:2203, 2217`
4. `L["OPTIONS_OFFSET_SLIDER_DESC"]` — used at `options.lua:2207, 2221`

All four use `or "fallback text"` patterns so no nil errors occur — but translations don't work.

### Root cause

Keys were added to enUS.lua during feature development but not propagated to other locales. Code was written with `or "fallback"` patterns instead of declaring the key in enUS.lua.

### Fix — Part A (add 22 keys to all non-English locales)

For each of the 10 non-English locale files, add the 22 keys (translated or English placeholder). The keys should be inserted at the alphabetically correct position within each locale file (after the existing OPTIONS_ keys). Recommended approach: add them after the last existing OPTIONS_* entry in each file, or use a script to insert them.

For the initial pass, copy the English values from enUS.lua (they'll appear in English until translated) and add the following comment above the block:

```lua
    -- Missing keys, awaiting translation (fallback to English)
```

### Fix — Part B (add 4 keys to enUS.lua)

Add these 4 key definitions to `Locale/enUS.lua` at the alphabetically correct positions:

```lua
    ["OPTIONS_OFFSET_EDIT_DESC"] = "Type a precise pixel offset and press Enter to apply it.",
    ["OPTIONS_OFFSET_SLIDER_DESC"] = "Drag to fine-tune this offset. The numeric field stays synchronized.",
    ["RANK_TITLE"] = "Champion",
    ["REALM"] = "Realm",
```

Note: `["REALM"]` (all-caps) is separate from the existing `["Realm"]` (camelCase) at line 195. Both are needed — code references both `L["REALM"]` (options.lua:1318, all-caps) and `L["Realm"]` (main.lua:823, camelCase).

### Verification

1. Set game client to zhCN (or any non-English locale)
2. Open `/tacotip` → verify border thickness control shows translated text (or English fallback)
3. Verify no "nil" text appears anywhere in the options UI

---

## P7 — Test suite: custom_pos/custom_anchor assertions fail

**Priority**: P4 (LOW)
**Files**: `TacoTip_Tests.lua`, `options.lua`
**Est. effort**: 1 line change (either test or defaults)

### Problem

`TacoTip_Tests.lua` line 70 asserts `d[k] ~= nil` for keys `"custom_pos"` and `"custom_anchor"`. However, both keys are **commented out** in `TT:GetDefaults()` (options.lua lines 130–131):

```lua
--custom_pos = nil,
--custom_anchor = nil,
```

The test **will fail** at runtime because `d.custom_pos` and `d.custom_anchor` are both `nil`.

**Impact**: Test suite has a latent failure. If tests are ever run automatically, they'd fail immediately.

### Root cause

Two conflicting intentions: the test expects these keys to exist in defaults (because they're used extensively at runtime), but the defaults intentionally omit them (because `nil` is the correct default for optional position data).

### Fix

**Option A (recommended)**: Remove `"custom_pos"` and `"custom_anchor"` from the test's assertion list. These keys intentionally have no default — `nil` is the correct value, and all read sites handle it with `or` fallbacks.

File: `TacoTip_Tests.lua`, line 70. Remove `"custom_pos"` and `"custom_anchor"` from the list.

**Option B**: Uncomment the two lines in `GetDefaults()`. This is acceptable but semantically wrong — they're not configurable defaults, they're missing-position sentinels.

---

## P8 — PawnGetSingleValueFromItem unprotected call

**Priority**: P4 (LOW)
**Files**: `pawn.lua`
**Est. effort**: 3 lines changed

### Problem

`PawnGetSingleValueFromItem` at `pawn.lua` line 57 is the **only** Pawn API call in the file that lacks a `pcall` wrapper:

```lua
return tonumber(select(2,PawnGetSingleValueFromItem(item,"\"Classic\":"..class..specIndex))) or 0
```

All three `PawnGetScaleColor` calls (lines 128, 147, 152) are properly wrapped in `pcall`. If `PawnGetSingleValueFromItem` throws (e.g., Pawn's internal scale data not yet initialized on SoD), the error propagates up through `GetItemScore` → `GetScore` → `main.lua` line 994, where it's caught by the outer `safeCall` at the tooltip hook level. This causes the **entire** `onTooltipSetUnit` function to abort — losing all TacoTip enhancements for that tooltip (not just Pawn).

**Impact**: On SoD, during the first 3 seconds after login, Pawn's scale data may not be initialized. If a player hovers a tooltip in that window and Pawn's item scoring throws, ALL TacoTip features are lost for that tooltip (GearScore, talents, class colors, everything — not just Pawn).

### Root cause

Line 57 was not updated to follow the same `pcall` pattern used by lines 128/147/152.

### Fix

Wrap the call in a local pcall:

Before:
```lua
return tonumber(select(2,PawnGetSingleValueFromItem(item,"\"Classic\":"..class..specIndex))) or 0
```

After:
```lua
local pcOk, pcResult = pcall(PawnGetSingleValueFromItem, item, "\"Classic\":"..class..specIndex)
return pcOk and (tonumber(select(2, pcResult)) or 0) or 0
```

### Dependencies

None. This is a standalone defensive fix that mirrors the existing pattern at lines 128/147/152.

---

## P9 — GetPlayerInfoByGUID structural fragility

**Priority**: P4 (LOW)
**Files**: `gearscore.lua` (line 311), `main.lua` (lines 1458, 1567)
**Est. effort**: 3–5 lines

### Problem

`GetPlayerInfoByGUID(guid)` at `gearscore.lua` line 311 is called directly with no pcall, no existence check, and no fallback — unlike the `GUIDIsPlayer` pattern at lines 87–91 which has a fallback. The API exists on all supported clients (11508, 20505, 30405 — Blizzard backported it to Classic-era), but the code has zero defense against:
- A future client deprecating the API
- The function returning nil for uncached players
- Any unexpected error

Additionally, the calls to `GearScore:GetScore()` at `main.lua` lines 1458 (character frame) and 1567 (inspect frame) are **not** wrapped in safeCall, unlike the tooltip path at line 1138 which uses safeCall. An error here would propagate uncaught and could break the PaperDollFrame or InspectFrame.

The tooltip path (main.lua:949) IS protected by the outer safeCall, but character/inspect are not.

**Impact**: Low on current clients (API exists). Fragility for future client updates.

### Fix

**Step 1**: Wrap the call at gearscore.lua line 311:

```lua
-- Before (line 311):
local _, PlayerEnglishClass = GetPlayerInfoByGUID(guid)

-- After:
local ok, _, playerClass = pcall(GetPlayerInfoByGUID, guid)
local PlayerEnglishClass = ok and playerClass or nil
```

**Step 2** (optional): Wrap `GearScore:GetScore()` calls in main.lua:

```lua
-- At line 1458 (character frame):
-- Before:
local gearscore, _, r, g, b = GearScore:GetScore("player")

-- After:
local gearscore, _, r, g, b = safeCall(GearScore.GetScore, GearScore, "player")
```

Same pattern at line 1567 (inspect frame):
```lua
local gearscore, _, r, g, b = safeCall(GearScore.GetScore, GearScore, InspectFrame.unit)
```

---

## P10 — Test: Borders:PlayerGetsClassBorder fragility

**Priority**: P4 (LOW)
**Files**: `TacoTip_Tests.lua`
**Est. effort**: 3–8 lines

### Problem

The `Borders:PlayerGetsClassBorder` test at lines 110–125 calls `TT:ApplyTooltipAppearance(GameTooltip, "player")` and asserts the border color is no longer white (1,1,1). It expects the class color to override the base white. However, in a WoWUnit test environment (or any environment where `UnitClass("player")` hasn't been mocked), the player's class color may not be resolvable, causing:

1. `storeTooltipPlayerClassColor` to return nil (line 200)
2. `getTooltipPlayerClassColor` to return `(1, 1, 1, false)`
3. The class-tint gate in `ApplyTooltipAppearance` (line 481) to skip the override
4. Border stays at (1,1,1) → assertion `not (r == 1 and g == 1 and b == 1)` fails

**Impact**: Test fails in mock environments, making the test suite unreliable.

### Root cause

The test has no mock for `UnitClass("player")` and no fallback path for when class resolution fails.

### Fix

Option A: Wrap the assertion in a precondition:

```lua
-- Before the assertion, verify class color is resolvable:
local _, testClass = UnitClass("player")
if (testClass) then
    local r, g, b = bf:GetBackdropBorderColor()
    IsTrue(not (r == 1 and g == 1 and b == 1), string.format("player border tinted (%.2f,%.2f,%.2f)", r or -1, g or -1, b or -1))
else
    print("WARN: Borders:PlayerGetsClassBorder skipped — UnitClass not resolvable")
end
```

Option B: Mock UnitClass using WoWUnit's Replace:

```lua
-- Before calling ApplyTooltipAppearance:
WoWUnit.Replace("UnitClass", function(...) return "Rogue", "ROGUE" end)
```

Option A is preferred as it's simpler and doesn't require WoWUnit's mocking API.

---

## P11 — Config key color channels missing range validation

**Priority**: P4 (LOW)
**Files**: `options.lua` (SafeSanitizeConfig)
**Est. effort**: 6 lines

### Problem

Six color channel config keys (`tooltip_border_color_r/g/b` and `tooltip_background_color_r/g/b`) have no range validation in `SafeSanitizeConfig`. They are float values expected to be in [0, 1]. If corrupted (NaN, >1, <0), they would pass through sanitization untouched and could produce invisible tooltips or visual artifacts.

These are currently set via Blizzard's ColorPickerFrame which clamps to 0–1, and read sites use `or 0` / `or 1` fallbacks, so the practical risk is low.

### Fix

Add range checks after the existing numeric checks (around line 215):

```lua
-- Color channel bounds (add after guild_rank_style check at line 214)
for _, key in ipairs{
    "tooltip_border_color_r", "tooltip_border_color_g", "tooltip_border_color_b",
    "tooltip_background_color_r", "tooltip_background_color_g", "tooltip_background_color_b",
} do
    local val = config[key]
    if (type(val) ~= "number" or val < 0 or val > 1) then
        config[key] = defaults[key]
    end
end
```

---

## Dependency Graph

```
P1 (tip_style)          ← independent
P2 (GetQuality)         ← independent
P3 (CAfter bleed)       ← independent
P4 (power bar cleanup)  ← independent
P5 (config change live) ← depends on P4 (partial overlap)
P6 (locale)             ← independent
P7 (test assertions)    ← independent
P8 (Pawn pcall)         ← independent
P9 (GetPlayerInfo)      ← independent
P10 (test fragility)    ← independent
P11 (color validation)  ← independent
```

All fixes are independent. They can be worked in any order and in parallel.

---

## Wave Plan

### Wave 1 — P1, P2, P3, P4, P8 (HIGH + critical, all independent)
| Task | File | Category | Skills |
|------|------|----------|--------|
| P1: Remove tip_style from booleanKeys | options.lua | quick | — |
| P2: Fix GetQuality channel swap | gearscore.lua | quick | — |
| P3: Add clearTooltipPlayerClassColor to non-unit branch | main.lua | quick | — |
| P4: Add power bar cleanup to clearTooltipVisuals | main.lua | quick | — |
| P8: Wrap PawnGetSingleValueFromItem in pcall | pawn.lua | quick | — |

### Wave 2 — P5, P6, P7, P9, P10, P11 (medium + low, all independent)
| Task | File | Category | Skills |
|------|------|----------|--------|
| P5: Add live power bar refresh on config toggle | options.lua | unspecified-low | — |
| P6a: Add 4 keys to enUS.lua | Locale/enUS.lua | writing | — |
| P6b: Add 22 keys to 10 non-English locales | Locale/*.lua | writing | — |
| P7: Fix test assertions for custom_pos/custom_anchor | TacoTip_Tests.lua | quick | — |
| P9: Wrap GetPlayerInfoByGUID in pcall | gearscore.lua | quick | — |
| P10: Fix Borders test fragility | TacoTip_Tests.lua | quick | — |
| P11: Add color channel range validation | options.lua | quick | — |
