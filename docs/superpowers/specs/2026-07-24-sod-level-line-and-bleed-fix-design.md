# SoD Level Line & clearTooltipVisuals Bleed-Through Fix

**Date:** 2026-07-24
**Project:** TacoTip-Gearscore-TBC
**Version target:** 0.6.3
**Author:** Hermes Agent (spec), AcidBomb (Pilsung) (review)

---

## 1. Problem Statement

Two independent bugs must be resolved before the 0.6.3 CurseForge deploy.

### 1.1 SoD: Level/Race/Class Line Missing for Players

**Observed:** On Season of Discovery (SoD, client 1.15.9, Classic Era codebase), the level/race/class line (e.g. "Level 60 Orc Warrior") appears correctly on NPC unit tooltips but does not appear on player tooltips.

**Not observed on:** TBC Anniversary — works correctly for both units and players. **TBC code is not to be modified.**

### 1.2 Bleed-Through: No clearTooltipVisuals for Class-Colored Text

**Observed:** A bleed-through test is failing. The `clearTooltipVisuals` function (main.lua:630) resets cached class color, border, guild line text, portrait, elite frame, and power bar — but does NOT reset the `TextLeft[i]` font strings that were modified with `|c` color codes by the class-color replacement (main.lua:793-800) and `colorizeText`. When the tooltip is recycled for non-unit content (items, spells, minimap POI), the old color-embedded text can persist or corrupt the new text display.

---

## 2. Root Cause Analysis

### 2.1 SoD Player Level Line

The Classic Era GameTooltip template (`Blizzard_SharedXML/Classic/GameTooltipTemplate.xml`) defines 8 TextLeft + 8 TextRight font strings. When `GameTooltip:SetUnit(unit)` fires on SoD:

| Scenario | text[1] | text[2] | text[3] |
|----------|---------|---------|---------|
| NPC unit | "NPCName" | "Level 60 Beast" | nil |
| Player, no guild | "PlayerName" | "Level 60 Orc Warrior" | nil |
| Player, with guild | "PlayerName" | "\<GuildName\>" | "Level 60 Orc Warrior" |

The addon's `onTooltipSetUnit` (main.lua:658) processes text lines inside the `if UnitIsPlayer(tooltipUnit)` block (L778-1039). The critical sequence:

1. **L703:** `text[2] = colorizeUnitLevelLine(tooltipUnit, text[2])` — operates only on text[2]. For guilded players, text[2] is `"<GuildName>"` (no level number), so the function is a no-op. The level line on text[3] is never colorized.

2. **L793-800:** Class-color replacement runs on `i=2,3` — this correctly catches the level line whether it's on text[2] or text[3].

3. **L804-838:** Guild handling. When `GetGuildInfo` returns a guild:
   - `guildLineIndex = 2`
   - `text[2]` is overwritten with the formatted guild string (e.g. `"<GuildName> (Rank)"`)
   - text[3] retains the level line — should survive

4. **L821-837 (show_guild_name = false):** `text[guildLineIndex] = ""` — this sets text[2] to empty string. If the level line was on text[2] (no-guild scenario), **it is destroyed** with no recovery path. No code re-adds the level text from `UnitLevel`/`UnitRace`/`UnitClass`.

5. **L1041-1047 (rendering):** Iterates up to `numLines`. Only non-empty `text[i]` entries are rendered. If the level line was destroyed in step 4, it's gone.

**Primary cause:** When `show_guild_name = false`, or when the guild bracket scan (L806-819) falsely identifies a match, text[guildLineIndex] is set to `""`, and no code restores the level/race/class line. Additionally, `colorizeUnitLevelLine` never reaches text[3] where the level lives for guilded players.

### 2.2 Bleed-Through (clearTooltipVisuals Gap)

`clearTooltipVisuals` (L630-656) performs:

| What | How | Present? |
|------|-----|----------|
| Class color cache | `clearTooltipPlayerClassColor` | ✅ |
| Border color | `resetTooltipBorderToDefault` | ✅ |
| Guild line text | `clearTooltipGuildLine` | ✅ |
| Portrait frames | `.Hide()` | ✅ |
| Elite frame | `.Hide()` | ✅ |
| Power bar | `.Hide()` | ✅ |
| **Class-colored font strings** | **Reset TextLeft[1..N]** | **❌ Missing** |

When the tooltip is recycled (OnTooltipCleared → OnTooltipSetSpell → OnTooltipSetItem transitions), the C++ engine repopulates font strings for the new content. However, on certain transition paths (e.g. `OnTooltipSetSpell` → `clearTooltipVisuals` → `itemToolTipHook` → `applyTooltipBorderOverlay`), the previous unit's `|c`-embedded text can be briefly visible or interfere with the border/backdrop rendering cycle, causing the bleed-through test to fail.

---

## 3. Fix Design

### 3.1 Fix A: Ensure Level Line Always Renders for Players

**Strategy:** After the player block completes, guarantee the level/race/class line exists in `text[]` or `linesToAdd`.

**Location:** After line 838 (end of guild handling), before the rendering loop (L1041).

**Logic:**

```lua
-- After guild handling, verify the level/race/class line survived.
-- SoD can place it on text[2] or text[3] depending on guild state,
-- and show_guild_name=false can destroy it.
if (UnitIsPlayer(tooltipUnit) and not unitLevelLinePreserved) then
    local level = UnitLevel(tooltipUnit)
    local race = UnitRace(tooltipUnit)
    local localizedClass, class = UnitClass(tooltipUnit)
    if (level and race and localizedClass) then
        local levelLine = format("Level %d %s %s", level, race, localizedClass)
        -- Apply class color to the new line
        if (TacoTipConfig.color_class) then
            local classc = getClassColor(class)
            if (classc) then
                levelLine = colorizeText(levelLine, classc.r, classc.g, classc.b)
            end
        end
        tinsert(linesToAdd, {levelLine})
    end
end
```

**Detection of "level line preserved":** After guild handling (L838), scan `text[2]` and `text[3]` for a level pattern (`"Level %d+"`). If neither has it, re-derive from Blizzard API and append.

**Why `linesToAdd` instead of `text[]`:** The rendering loop at L1041 compacts `text[]` by skipping empty entries. Adding to `linesToAdd` guarantees it appears as a new tooltip line with correct positioning.

### 3.2 Fix B: clearTooltipVisuals for Class-Colored Text

**Strategy:** Track which tooltip font strings were modified with `|c` color codes, then reset them in `clearTooltipVisuals`. Follow the same pattern as `clearTooltipGuildLine`.

**Implementation:**

1. **Add a new function `clearTooltipColoredText(tooltip)`:**
   - Iterates over `tooltip.TacoTipColoredLineIndices` (a table tracking which `TextLeft[i]` were modified)
   - Resets each tracked font string to its stored original text (saved before coloring)
   - Clears the tracking table

2. **In the player class-coloring block (L793-800):** Before modifying `text[i]`, save the original text to `tooltip.TacoTipOriginalTexts[i]` and record the index in `tooltip.TacoTipColoredLineIndices`.

3. **In `clearTooltipVisuals` (L630):** Add `clearTooltipColoredText(tooltip)` after `clearTooltipGuildLine`.

4. **Fallback for missing original text:** If no original was saved, reset the font string to empty string to prevent bleed.

**Note on font string lifecycle:** When Blizzard's C++ engine calls `SetUnit`, it overwrites the font strings with fresh text. The clear step is a defence-in-depth for transitions where the addon's own `SetText()` calls from a previous frame persist through non-`SetUnit` transitions (spell, item, clear).

### 3.3 Test Updates

1. **Add a new test `TT-ColoredText` group** with:
   - `NoBleedToNonUnitTooltip`: Apply player class colors, clear, verify TextLeft2/3 are reset
   - `SoDLevelLineShowsForPlayer`: Mock SoD tooltip layout (guild on line 2, level on line 3), verify level line still renders
   - `SoDLevelLineShowsForPlayerNoGuild`: Mock player without guild, verify level line on line 2

2. **Update existing bleed tests** (`Borders:NoBleedToNonUnitTooltip`, `Borders:NoBleedToItemTooltip`) to also assert font string text is clean after clear.

### 3.4 What Will NOT Change

- TBC Anniversary tooltip code — confirmed working, no modifications
- Border/portrait/guild line clear logic — already correct, just adding the colored-text clear
- Guild format strings — already fixed in 0.6.2

---

## 4. Verification Plan

| Gate | Command / Method | Expected |
|------|-----------------|----------|
| Lua syntax | `luac -p main.lua` | Clean parse |
| Test suite | `/tttest` in-game on SoD client | All 9 test groups pass (8 existing + 1 new) |
| SoD player tooltip | Hover a player in SoD | "Level XX Race Class" visible |
| SoD NPC tooltip | Hover an NPC in SoD | Level line unchanged |
| Bleed test | Run `TacoTip-Borders:NoBleed*` | Border + text reset after clear |
| TBC regression | `/tttest` on TBC Anniversary | All existing tests pass; TBC code untouched |

---

## 5. Spec Self-Review

- [x] No placeholders — all code paths identified with line numbers
- [x] Internal consistency — Fix A and Fix B are independent, can be implemented in either order
- [x] Scope — only SoD + clearTooltipVisuals; TBC explicitly excluded
- [x] Ambiguity — "level line" defined as the "Level XX Race Class" string; "bleed" defined as color-embedded text persisting after tooltip recycle
- [x] Test plan covers both new behavior and regression on TBC
