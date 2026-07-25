---
name: tacotip-dual-engine-architecture
description: Explains the true "Dual Engine" architecture (Classic Era vs TBC/Wrath simultaneous support) and how TacoTip-Gearscore-TBC handles multi-client compatibility.
---

# TacoTip Dual Engine Architecture

**"Dual Engine" does NOT refer to GearScore and Pawn.** It refers to TacoTip's ability to run simultaneously on multiple distinct WoW game engines (Classic Era, TBC Anniversary, WotLK, and Titanforge) using a single, unified codebase.

This is the most critical architectural concept in the project. Any changes made to the codebase MUST account for the fact that the code will execute on entirely different game clients.

## Core Multi-Client Detection

TacoTip prevents loading on unsupported clients (like Retail or Cataclysm) and branches logic internally by detecting the `clientBuildMajor` version:

```lua
local interfaceVersion = select(4, GetBuildInfo()) or 0
local clientBuildMajor = math.floor(interfaceVersion / 10000)

-- 1 = Classic Era (Vanilla, SoD, SoM)
-- 2 = TBC (Burning Crusade Classic / Anniversary)
-- 3 = WotLK (Wrath Classic, Titanforge Chinese Version 3.80.1)
```

## Mandatory Reference Documents

Before modifying features that interact with Blizzard APIs (e.g., Guilds, Talents, or UI settings), you MUST read the exact branch logic defined in the following reference documents:

1. **`references/wiring.md`**: Details how `clientBuildMajor` is transformed into boolean flags (`isClassic`, `isTBC`, `isWotlk`) in `LibClassicInspector` to gracefully handle API differences across the 3 major game versions.
2. **`references/ui_registration.md`**: Explains how the settings UI branches between modern `Settings.RegisterCanvasLayoutCategory` and legacy `InterfaceOptions_AddCategory` depending on the client.
