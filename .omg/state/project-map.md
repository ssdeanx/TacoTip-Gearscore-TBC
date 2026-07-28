# Project Map

This document maps the files in **TacoTip-Gearscore-TBC** to their architectural responsibilities, key functions, exposed globals, and dependencies.

## Module Breakdown

### 1. Core Logic & Calculations
- **[gearscore.lua](file:///home/sam/TacoTip-Gearscore-TBC/gearscore.lua)**
  - *Responsibilities:* Computes GearScore and average item level based on item slots, character level, and quality/rarity.
  - *Globals/API Exposed:* `TT_GS` (containing formulas, bracket colors via `GetQuality`, and item level lookup helper `GetItemLevel`).
  - *Internal Structure:* Holds tables like `GS_ItemTypes`, `GS_Quality`, and slot scaling coefficients.

- **[pawn.lua](file:///home/sam/TacoTip-Gearscore-TBC/pawn.lua)**
  - *Responsibilities:* Integrates optional Pawn addon scores into unit and item tooltips.
  - *Globals/API Exposed:* `TT_PAWN`.
  - *Key Integration:* Detects Pawn availability safely and resolves scale values using client-specific scale naming patterns.

### 2. UI Styling & Media Assets
- **[textures.lua](file:///home/sam/TacoTip-Gearscore-TBC/textures.lua)**
  - *Responsibilities:* Handles texture mappings, status bar textures, class icon coordinates, and registers default textures.
  - *Optional Integration:* Hooks into `LibSharedMedia-3.0` to discover user-installed custom fonts, borders, and bar textures.

### 3. Settings & Options Panel
- **[options.lua](file:///home/sam/TacoTip-Gearscore-TBC/options.lua)**
  - *Responsibilities:* Defines the settings configuration structure, config initialization and sanitization logic (`SafeSanitizeConfig`), options UI registration (compatible with both modern canvas layout and legacy category frames), and renders the options-only preview tooltip.
  - *Saved Variables:* Reads and writes `TacoTipConfig`.
  - *Exposed API:* `TT.RefreshOptionsUI`, `TT.GetDefaults`, `TT.ApplyConfigDefaults`.

### 4. Runtime Hooking & Event Orchestration
- **[main.lua](file:///home/sam/TacoTip-Gearscore-TBC/main.lua)**
  - *Responsibilities:* Runtime entry point, boots libraries, hooks all tooltips (`GameTooltip`, `ShoppingTooltip1/2`, `ItemRefTooltip`), registers event scripts, renders custom status bars (health, mana/power), dynamically applies class-colored borders using NineSlice overlays on TBC Anniversary clients, and coordinates spec/talent refreshes upon receiving inspector callback events.
  - *Exposed API:* `TT.ApplyTooltipAppearance`, `TT.SyncTooltipMover`.

### 5. Localization & Documentation
- **[Locale/enUS.lua](file:///home/sam/TacoTip-Gearscore-TBC/Locale/enUS.lua)** (Source of Truth) and other translations (`deDE`, `esES`, `esMX`, `frFR`, `itIT`, `koKR`, `ptBR`, `ruRU`, `zhCN`, `zhTW`).
  - *Responsibilities:* Maps localization keys to language-specific display text. Populates `TACOTIP_LOCALE`.

- **[docs/classic-tooltip-api-reference.md](file:///home/sam/TacoTip-Gearscore-TBC/docs/classic-tooltip-api-reference.md)**
  - *Responsibilities:* Complete reference of Blizzard `GameTooltip` C++ API methods for Classic Era / TBC Anniversary, documenting signatures, availability, current usage, and modernization refactoring opportunities.

## Dependency Map & Communication Flow
```
        [ TacoTip.toc ]
               │ (Load Order)
               ▼
   [ Bundled Libraries / Libs/ ]
               │
               ▼
       [ Locale/*.lua ]
               │
               ▼
     [ gearscore.lua (TT_GS) ]
               │
               ▼
       [ pawn.lua (TT_PAWN) ]
               │
               ▼
     [ textures.lua (Media) ]
               │
               ▼
     [ options.lua (Config) ]
               │
               ▼
        [ main.lua (Runtime) ]
```
