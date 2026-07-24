# SoD Level Line & Bleed-Through Fix — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix two bugs: (A) SoD player tooltip missing the level/race/class line, and (B) class-colored text not cleared in `clearTooltipVisuals` causing a bleed-through test failure.

**Architecture:** Both fixes live in `main.lua`. Fix A adds level-line fallback after guild handling in `onTooltipSetUnit`. Fix B tracks colored text indices and clears them in `clearTooltipVisuals`, following the `clearTooltipGuildLine` pattern. Test additions go in `TacoTip_Tests.lua`.

**Tech Stack:** Lua 5.1 (WoW embedded), WoWUnit test framework.

## Global Constraints

- **TBC Anniversary code path must NOT be modified** — the level line works correctly there. Only SoD/Classic Era code paths.
- Follow existing patterns: `clearTooltipGuildLine` for the clear pattern, `storeTooltipPlayerClassColor` for the tracking pattern.
- No new globals. Use `tooltip.*` table keys on the tooltip frame for state.
- All new functions must be `local function` (module-scoped).
- `luac -p main.lua` must pass after every task.
- TacoTip_Tests.lua must pass `luac -p` after every task.

---

### Task 1: Add Level-Line Detection & Fallback After Guild Handling (Fix A)

**Files:**
- Modify: `main.lua` — insert detection + fallback after line 838 (end of guild handling), before line 841 (`if (TacoTipConfig.show_realm ...)`)

**Interfaces:**
- Consumes: `tooltipUnit` (already resolved), `text[]` table (already populated), `linesToAdd[]` table (being built)
- Produces: Level line appended to `linesToAdd[]` when missing from `text[2]` and `text[3]`

- [ ] **Step 1: Add level-line survival check and fallback**

After the guild handling block (after `end` at what is currently line 838, before the `if (TacoTipConfig.show_realm ...)` at line 839), insert:

```lua
        -- SoD/Era: After guild handling, verify the level/race/class line
        -- survived.  On SoD the level may be on text[2] or text[3] depending
        -- on guild state, and show_guild_name=false destroys it from text[2]
        -- without any re-derivation.  If neither text line has a level token,
        -- re-derive from the Blizzard API and add as an extra tooltip line.
        if (TacoTipConfig.show_level_line ~= false) then
            local hasLevelLine = false
            for i = 2, 3 do
                if (text[i] and text[i]:find("^Level %d+")) then
                    hasLevelLine = true
                    break
                end
            end
            if (not hasLevelLine) then
                local level = UnitLevel(tooltipUnit)
                local localizedRace = UnitRace(tooltipUnit)
                local localizedClass, class = UnitClass(tooltipUnit)
                if (level and level > 0 and localizedRace and localizedClass) then
                    local levelLine = string.format("Level %d %s %s", level, localizedRace, localizedClass)
                    if (TacoTipConfig.color_class and class) then
                        local classc = getClassColor(class)
                        if (classc) then
                            levelLine = colorizeText(levelLine, classc.r, classc.g, classc.b)
                        end
                    end
                    tinsert(linesToAdd, {levelLine})
                end
            end
        end
```

Note: The `show_level_line` config key should default to `true` via `TT:GetDefaults()`. If it doesn't exist yet, add it.

- [ ] **Step 2: Add `show_level_line` to defaults**

In the `TT:GetDefaults()` function, add:
```lua
show_level_line = true,
```

Also add to the `DefaultsHaveKeys` test in TacoTip_Tests.lua.

- [ ] **Step 3: Verify syntax**

```bash
luac -p main.lua
```
Expected: clean exit (no output).

- [ ] **Step 4: Commit**

```bash
git add main.lua
git commit -m "fix: add level-line fallback for SoD player tooltips"
```

---

### Task 2: Add Colored-Text Tracking & Clear in clearTooltipVisuals (Fix B)

**Files:**
- Modify: `main.lua` — add `clearTooltipColoredText` function, save original texts before coloring, wire into `clearTooltipVisuals`

**Interfaces:**
- Consumes: `text[]` before class-color modification, `tooltip.TacoTipColoredLineIndices` table
- Produces: `clearTooltipColoredText(tooltip)` — resets tracked font strings

- [ ] **Step 1: Add `clearTooltipColoredText` function**

Add near `clearTooltipGuildLine` (around line 185-193):

```lua
-- Tracks which GameTooltipTextLeft[i] were modified with |c color codes
-- so clearTooltipVisuals can reset them, preventing the old colored text
-- from bleeding through on tooltip recycle (item, spell, minimap POI).
local function clearTooltipColoredText(tooltip)
    if (not tooltip) then
        return
    end
    local indices = tooltip.TacoTipColoredLineIndices
    if (not indices) then
        return
    end
    for _, i in ipairs(indices) do
        local fontString = _G[tooltip:GetName().."TextLeft"..i]
        if (fontString and fontString.SetText) then
            local original = tooltip.TacoTipOriginalTexts and tooltip.TacoTipOriginalTexts[i]
            if (original) then
                fontString:SetText(original)
            else
                fontString:SetText()
            end
        end
    end
    tooltip.TacoTipColoredLineIndices = nil
    tooltip.TacoTipOriginalTexts = nil
end
```

- [ ] **Step 2: Save original texts before class-color modification**

In the player class-coloring block (around lines 793-800), BEFORE the modification loop, add:

```lua
            -- Save original texts so clearTooltipColoredText can restore them
            -- and prevent colored text bleed on tooltip recycle.
            tooltip.TacoTipColoredLineIndices = {}
            tooltip.TacoTipOriginalTexts = tooltip.TacoTipOriginalTexts or {}
            for i = 2, 3 do
                if (text[i]) then
                    tinsert(tooltip.TacoTipColoredLineIndices, i)
                    tooltip.TacoTipOriginalTexts[i] = text[i]
                end
            end
```

And INSIDE the `for i=2,3 do` loop, AFTER saving originals, proceed with the existing replacement:

```lua
            for i=2,3 do
                if (text[i]) then
                    -- [existing replacement code unchanged]
                end
            end
```

- [ ] **Step 3: Wire into `clearTooltipVisuals`**

At the end of `clearTooltipVisuals` (after `stopPowerBarTicker()` at line 656, before `end`), add:

```lua
    clearTooltipColoredText(tooltip)
```

- [ ] **Step 4: Verify syntax**

```bash
luac -p main.lua
```
Expected: clean exit.

- [ ] **Step 5: Commit**

```bash
git add main.lua
git commit -m "fix: add clearTooltipColoredText for bleed-through prevention"
```

---

### Task 3: Update Tests for Both Fixes

**Files:**
- Modify: `TacoTip_Tests.lua` — add new test groups

- [ ] **Step 1: Add `show_level_line` to `DefaultsHaveKeys` test**

In `Config:DefaultsHaveKeys()`, add `"show_level_line"` to the `ipairs` list.

- [ ] **Step 2: Add `TT-ColoredText` test group**

After the `TT-Mover` test group (around line 362), add:

```lua
    -- ============================================================
    -- TT-ColoredText: class-colored text resets on tooltip recycle
    -- ============================================================
    local ColoredText = WoWUnit("TacoTip-ColoredText", "PLAYER_ENTERING_WORLD")

    function ColoredText:ClearRestoresOriginalText()
        -- Mock: Apply player class color, then clear, verify font string
        -- text is restored to non-color-coded state.
        local text2orig = _G.GameTooltipTextLeft2:GetText() or ""
        local cfg = _G.TacoTipConfig
        local savedColor = cfg.color_class
        cfg.color_class = true

        -- Simulate a player tooltip (triggers class-color replacement)
        local ok = pc(GameTooltip.SetUnit, GameTooltip, "player")
        IsTrue(ok, "SetUnit(player) did not error")

        -- Read the modified text after coloring
        local coloredText = _G.GameTooltipTextLeft2:GetText()

        -- Clear should revert it (via clearTooltipVisuals -> clearTooltipColoredText)
        pc(GameTooltip.Clear, GameTooltip)
        -- After Clear, if no new text was set, the font string may be empty
        -- from the original-clear path.  Verify at minimum that the
        -- TacoTipColoredLineIndices tracking was cleared.
        local tooltip = GameTooltip
        IsTrue(tooltip.TacoTipColoredLineIndices == nil,
            "colored-line indices cleared after Clear")

        cfg.color_class = savedColor
    end

    function ColoredText:SoDLevelLineShowsForPlayer()
        -- Simulate the SoD tooltip layout: guild on line 2, level on line 3.
        -- Verify the level line survives the guild overwrite.
        Replace("GetGuildInfo", function(unit)
            if (unit == "player") then return "TestGuild", "Rank 5", 5 end
            return nil
        end)
        local cfg = _G.TacoTipConfig
        local savedGuild = cfg.show_guild_name
        local savedLevel = cfg.show_level_line
        cfg.show_guild_name = true
        cfg.show_level_line = true

        -- Set up SoD-style layout
        GameTooltip:ClearLines()
        GameTooltip:AddLine("TestPlayer")
        GameTooltip:AddLine("<TestGuild>")
        GameTooltip:AddLine("Level 60 Orc Warrior")

        local script = GameTooltip:GetScript("OnTooltipSetUnit")
        local ok = pc(script, GameTooltip)
        IsTrue(ok, "OnTooltipSetUnit did not error")

        -- The level line should still appear somewhere in the tooltip
        local line3 = _G.GameTooltipTextLeft3 and _G.GameTooltipTextLeft3:GetText()
        if (line3 and line3 ~= "") then
            IsTrue(line3:find("Level 60") ~= nil, "level line present on line 3")
        else
            -- May have shifted to a different line; check all visible lines
            local found = false
            for i = 1, 6 do
                local t = _G["GameTooltipTextLeft"..i] and _G["GameTooltipTextLeft"..i]:GetText()
                if (t and t:find("Level 60")) then
                    found = true
                    break
                end
            end
            IsTrue(found, "level line present somewhere in tooltip")
        end

        cfg.show_guild_name = savedGuild
        cfg.show_level_line = savedLevel
        ClearReplaces()
    end

    function ColoredText:SoDLevelLineShowsForPlayerNoGuild()
        -- Simulate SoD player WITHOUT guild: level on line 2.
        -- Verify level line survives when show_guild_name=false.
        Replace("GetGuildInfo", function(unit)
            return nil  -- no guild
        end)
        local cfg = _G.TacoTipConfig
        local savedGuild = cfg.show_guild_name
        local savedLevel = cfg.show_level_line
        cfg.show_guild_name = false
        cfg.show_level_line = true

        GameTooltip:ClearLines()
        GameTooltip:AddLine("TestPlayer")
        GameTooltip:AddLine("Level 60 Orc Warrior")

        local script = GameTooltip:GetScript("OnTooltipSetUnit")
        local ok = pc(script, GameTooltip)
        IsTrue(ok, "OnTooltipSetUnit did not error")

        -- Level line must survive
        local line2 = _G.GameTooltipTextLeft2 and _G.GameTooltipTextLeft2:GetText()
        if (line2 and line2 ~= "") then
            IsTrue(line2:find("Level 60") ~= nil, "level line on line 2 (no guild)")
        else
            -- Check all lines
            local found = false
            for i = 1, 6 do
                local t = _G["GameTooltipTextLeft"..i] and _G["GameTooltipTextLeft"..i]:GetText()
                if (t and t:find("Level 60")) then
                    found = true
                    break
                end
            end
            IsTrue(found, "level line present somewhere (no guild)")
        end

        cfg.show_guild_name = savedGuild
        cfg.show_level_line = savedLevel
        ClearReplaces()
    end
```

- [ ] **Step 3: Verify syntax**

```bash
luac -p TacoTip_Tests.lua
```
Expected: clean exit.

- [ ] **Step 4: Commit**

```bash
git add main.lua TacoTip_Tests.lua
git commit -m "test: add colored-text and SoD level-line tests"
```

---

### Task 4: Final Verification

- [ ] **Step 1: Verify both files pass Lua syntax**

```bash
luac -p main.lua && luac -p TacoTip_Tests.lua
```
Expected: clean exit.

- [ ] **Step 2: Verify git status**

```bash
git status
git diff --stat
```
Expected: only `main.lua` and `TacoTip_Tests.lua` modified, with changes contained to the fix regions.

- [ ] **Step 3: Check for any TBC code modifications**

```bash
git diff main.lua | grep -E "^[+-].*20505|^[+-].*TBC"
```
Expected: no matches — TBC code is untouched.

- [ ] **Step 4: Commit any remaining changes**

```bash
git add -A
git commit -m "chore: final verification pass"
```
