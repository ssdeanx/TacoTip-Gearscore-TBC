# Architecture, Modules & Subsystems

## 1. Runtime Load Order (`TacoTip.toc`)

TacoTip (`v1.0.5`) loads files in strict dependency order:

1. **Libraries (`Libs/`):**
   - `Libs/LibStub/LibStub.lua`, `Libs/CallbackHandler-1.0/CallbackHandler-1.0.lua`, `Libs/LibDetours-1.0/LibDetours-1.0.lua` (`SecureHook` / `SecureUnhook`)
   - `Libs/LibForeverInspector/LibForeverInspector.lua` — Cross-client detection (`IsRetail`, `IsForever`, `IsClassic`, `IsTBC`, `IsAnniversary`, `IsWotlk`, `IsTitanforge`), `CanInspect`/`DoInspect`, recent cache export/prune/restore (`ExportRecentEntry`, `PruneAndTrimRecentTable`, `RestoreRecentCache`), classic + Camelot trait/talent queries (`GetForeverInspectTalentData`, `GetForeverTalentData`), `GetInventoryItemMixin`, and secret-safe helpers
   - `Libs/LibDataBroker-1.1/LibDataBroker-1.1.lua` & `Libs/LibDBIcon-1.0/LibDBIcon-1.0.lua` — Minimap launcher (`TT:SetMinimapIconShown`)

2. **Localization (`Locale/`):**
   - `deDE`, `esES`, `esMX`, `frFR`, `itIT`, `koKR`, `ptBR`, `ruRU`, `zhCN`, `zhTW`, followed **last** by `enUS.lua` (239 base keys + `_G.TacoTipApplyLocale()`).

3. **Core Modules:**
   - `gearscore.lua` (`_G.TT_GS`) — `GetQuality`, `GetItemScoreFromInfo`, `GetItemScore`, `GetItemHunterScore`, `GetScore`; frozen formulas & client brackets (`200` Classic/Forever, `400` TBC, `1000` Retail/Titanforge).
   - `pawn.lua` (`_G.TT_PAWN`) — `GetItemScore`, `GetScore` (spec matching + throttled late-load Pawn integration).
   - `textures.lua` — Media catalog (`LSM` optional), UTF-8 `detectScripts` + `PickScriptFont` / `GetScriptFontPath` resolving Cyrillic (`NotoSans-Regular.ttf`), Chinese (`WenQuanYiMicroHei.ttf`), and Korean (`NanumGothic-Regular.ttf`).
   - `options.lua` — SavedVariables migration (`SafeSanitizeConfig`), slash commands, Blizzard Settings canvases (`TacoTip`, `Tooltips`, `Positioning`, `Character & Inspect`), and lazy `/tt` standalone Dashboard (`TacoTipDashboard`, `TT:ShowStandaloneDashboard`).
   - `main.lua` (`_G.TT`) — Unit/spell/`FriendsTooltip`/World Map hooks, secrecy guards (`isSecretValue`, `safeEquals`, `tooltipDataReadable`, `safeUnit*`), script font pipeline (`ApplyTooltipFonts`, `ApplyFontIfNeeded`), `FojjiCore` guard (`blockFojjiCoreScoreRow`), GearScore/Pawn memoization, `recentCache` persistence, PaperDoll/Inspect overlays + Forever stats footer & hover breakdown (`ShowCharacterStatTooltip`), Progression & Trophy engine, and `/tt diag` telemetry.

---

## 2. Exported Core Subsystems (`main.lua`)

- **GearScore & Pawn Memoization:** `TT.getGearScoreMemo`, `setGearScoreMemo`, `clearGearScoreMemo`, `getPawnScoreMemo`, `setPawnScoreMemo` cache computed unit scores by GUID + slot snapshot.
- **Persistent Recent Cache:** `TT:WarmGearItemData`, `SaveRecentInspectEntry`, `SaveRecentInspectCache`, `RestoreRecentInspectCache` persist up to 128 inspect snapshots in `TacoTipConfig.recentCache` across `/reload`.
- **Character & Inspect Overlays:** `TT:InitCharacterFrame`, `TT:RefreshCharacterFrame`, `TT:InitInspectFrame`, `TT:RefreshInspectFrame`, plus Forever's bottom card `TT:RefreshForeverCharacterStatsFooter` (`TT.foreverStatsFooter`) and detailed iLvl/GearScore hover tooltips (`ShowCharacterStatTooltip` / `HideCharacterStatTooltip` / `AttachStatHoverFrame`).
- **Gear Progression & Trophies:** `TROPHY_DEFINITIONS` (10 unlockable trophies), client step sizes (`GetGearLevelStepSize`: `25` Classic/Forever, `60` TBC, `100` WotLK, `150` Retail), `GetGearLevelInfo`, `GetGearScoreProgressCap`, `GetProgressionBarSnapshots`, `CheckTrophies`, `EvaluatePlayerEquipment`, `ClearPlayerProgression`, `ExportProgressionReport` (persisted per character in `TacoTipConfig.progression`).
- **Diagnostics & Telemetry:** `TT.LOAD_STAGE`, `TT.LOAD_OK`, `TT:RecordError`, `TT:RecordWarning`, `TT:NoteSecretRefusal`, `TT:RestrictionSnapshot`, `TT:CollectDiagnostics`, `TT:PrintDiagnostics`, `TT:FormatDiagnosticTraces`, `TT:FormatDiagnosticExport`, `TT:ClearDiagnosticLogs`.
- **Third-Party Guard (`FojjiCore`):** `blockFojjiCoreScoreRow()` strips duplicate `FojjiCore` / `FojjiCore_BiS` score lines at source to prevent tooltip bloat and secret/taint cascades.

---

## 3. Slash Commands & SavedVariables

- **Slash Aliases (`options.lua`, `SLASH_TACOTIP1..7`):** `/tacotip`, `/tooltip`, `/tip`, `/tt`, `/gs`, `/gearscore`, `/taco` (plus companion `/ex`, `/extras`, `/tte`, `/ttgssync` in `TacoTip_Extras`).
- **Subcommands:** `<empty>` (Dashboard), `custom` / `move` / `unlock` / `mover`, `default`, `save`, `reset`, `minimap` / `icon`, `anchor <topleft|topright|bottomleft|bottomright|center>`, `lb` / `rank` / `ranks` / `leaderboard`, `diag` / `diagnostics`, `report` / `export`, `discord` / `community`, `help`.
- **SavedVariables (`TacoTipConfig`):** Style/display toggles, appearance/media strings & RGBA colors, 4-element `custom_pos` + `custom_anchor`, PaperDoll/Inspect X/Y offsets, `locale_override`, `progression`, and `recentCache`.

---

## 4. Lua 5.1 Compiler Budgets & Workshop Separation

- `main.lua` sits near Lua 5.1's **200 file-scope local limit** and `onTooltipSetUnit` sits near the **60-upvalue ceiling** — group helpers inside `do ... end` blocks and expose shared helpers on `TT.*`.
- `createDashboard()` in `options.lua` wraps each tab in `do ... end` for the same 200-local limit.
- Non-shipped paths (`Tests/`, `Tools/`, `desks/`, `bench/`, `OLD/`, `TacoTip_Extras/`, `.omg/`, `MEMORY.md`, `AGENTS.md`) are excluded from the core release zip via `.gitattributes`.
