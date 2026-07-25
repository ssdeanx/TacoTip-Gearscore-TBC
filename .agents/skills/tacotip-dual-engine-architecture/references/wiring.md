# Dual Engine Logic Branches (Multi-Client)

The "Dual Engine" architecture allows TacoTip to run seamlessly on completely different WoW client versions at the same time without needing separate `.toc` files or separate addon downloads.

## The Version Detection Mechanism

Every file that requires version-specific behavior uses the following baseline to detect the client:

```lua
local interfaceVersion = select(4, GetBuildInfo()) or 0
local clientBuildMajor = math.floor(interfaceVersion / 10000)
```

## LibClassicInspector Branching

Data extraction logic (Talents, Guilds, Achievements) changes drastically between WoW expansions. `LibClassicInspector` defines three explicit boolean constants to branch this logic securely:

```lua
local isWotlk = clientBuildMajor == 3
local isTBC = clientBuildMajor == 2
local isClassic = clientBuildMajor == 1
```

### How Data Extraction is Split:
1.  **Talents:** 
    *   `isClassic` (Vanilla/SoD): Skips talent extraction. Talents are not easily accessible via Blizzard's API without massive inspection overhead.
    *   `isTBC` / `isWotlk`: Utilizes the expansion-specific `NotifyInspect` and `GetTalentTabInfo` methods.
2.  **Achievements:**
    *   `isWotlk`: Queries achievement APIs.
    *   `isClassic` / `isTBC`: Skips completely (feature did not exist).
3.  **Guild Information:**
    *   `GetGuildInfo` works smoothly in TBC/Wrath, but frequently fails or returns `nil` in modern Classic Era (SoD 1.15.x) for non-player units until they are explicitly inspected or due to API deprecations. TacoTip falls back to parsing the raw `GameTooltip` text (via Regex `<(.*)>`) when the API fails.

## Titanforge Chinese Version Support

The Chinese Titanforge servers use a Wrath-family client reporting a `3.80.1` build (`38001`). 
Because TacoTip isolates WotLK logic using `clientBuildMajor == 3`, Titanforge is natively supported by the "Dual Engine" without any specialized logic overrides. The engine gracefully treats it as a standard Wrath client.
