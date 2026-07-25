# Options UI Dual-Registration Architecture

This document dictates the rules for modifying the TacoTip configuration menu inside `options.lua`.

## The Problem
TacoTip targets both modern WoW clients (Retail, War Within API base) and legacy WoW clients (Classic Era). The options API completely changed between these versions.

## The Solution: Dual-Registration

TacoTip uses a conditional branch to detect the presence of the modern `Settings` API. 
**NEVER delete the legacy fallback branch** (`InterfaceOptions_AddCategory`) under the assumption that it is dead code.

### Registration Logic Map

```lua
-- Modern Registration (Dragonflight / TWW / Modern Retail API)
if Settings and Settings.RegisterCanvasLayoutCategory then
    local category = Settings.RegisterCanvasLayoutCategory(rootFrame, rootFrame.name)
    Settings.RegisterAddOnCategory(category)
    
    local subcategory = Settings.RegisterCanvasLayoutSubcategory(category, childFrame, childFrame.name)
    Settings.RegisterAddOnCategory(subcategory)

-- Legacy Registration (Classic Era / Wrath / TBC)
else
    rootFrame.name = "TacoTip Gearscore TBC"
    InterfaceOptions_AddCategory(rootFrame)
    
    childFrame.parent = rootFrame.name
    InterfaceOptions_AddCategory(childFrame)
end
```

### Scrolling Architecture

Because options menus can get tall, child pages must support scrolling.
1. The scrollable child pages proxy mouse-wheel input through their parent frames.
2. The page builder dynamically counts manual spacing to compute scroll height so long pages don't cut off visually.
3. If you add new configuration toggles in `options.lua`, verify that the total height calculation is updated so the frame continues to scroll cleanly.
