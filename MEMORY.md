# TacoTip — Project Memory

> **Version:** `1.0.7` | **CurseForge ID:** `1555962` | **License:** MIT (`AcidBomb` & `kebabstorm`)  
> **Upstream Lineage:** Based on original TacoTip by `kebabstorm` (`https://www.curseforge.com/wow/addons/tacotip-gearscore-talents`) and `GearScoreLite` (`Mirrikat45 & others`)  
> **Supported Interfaces:** `11509` (Classic Era / SoD), `20506` (TBC Anniversary), `38002` (WotLK Titanforge), `16001` (WoW Forever / Camelot), `120105` (Retail)  
> **Companion Addon:** `TacoTip_Extras/` (`v1.3.2`, separate package & CurseForge project — see [TacoTip_Extras/MEMORY.md](file:///home/sam/TacoTip-Gearscore-TBC/TacoTip_Extras/MEMORY.md))

---

## 1. Architecture & Runtime Load Sequence (`TacoTip.toc`)

TacoTip runs a single codebase across five WoW client families, loaded in strict dependency order:

1. **Libraries (`Libs/`):** `LibStub`, `CallbackHandler-1.0`, `LibDetours-1.0` (`SecureHook` / `SecureUnhook`), `LibForeverInspector`, `LibDataBroker-1.1`, `LibDBIcon-1.0`.
2. **Localization (`Locale/`):** `deDE`, `esES`, `esMX`, `frFR`, `itIT`, `koKR`, `ptBR`, `ruRU`, `zhCN`, `zhTW`, followed **last** by `Locale/enUS.lua` (**239 base keys** + `_G.TacoTipApplyLocale()` copy-merge). `gearscore.lua` re-runs `TacoTipApplyLocale()` on `ADDON_LOADED` once `TacoTipConfig.locale_override` is readable from SavedVariables.
3. **Core Runtime Modules:**
   - [gearscore.lua](file:///home/sam/TacoTip-Gearscore-TBC/gearscore.lua) (`_G.TT_GS`): Item/player GearScore & HunterScore calculators (`GetQuality`, `GetItemScoreFromInfo`, `GetItemScore`, `GetItemHunterScore`, `GetScore`), early slash bootstrap (`registerBootstrapSlash`), and throttled `RequestLoadItemDataByID` (`2.0s` cooldown).
   - [pawn.lua](file:///home/sam/TacoTip-Gearscore-TBC/pawn.lua) (`_G.TT_PAWN`): Client-aware Pawn scale bridge (`GetItemScore`, `GetScore`), dual-spec caching, and throttled late-load handling.
   - [textures.lua](file:///home/sam/TacoTip-Gearscore-TBC/textures.lua): Built-in/SharedMedia catalog (`LSM`), UTF-8 script detection (`detectScripts`), and font fallback resolver (`PickScriptFont`, `GetScriptFontPath`) mapping Cyrillic → `Media/Fonts/NotoSans-Regular.ttf`, Chinese → `WenQuanYiMicroHei.ttf`, Korean → `NanumGothic-Regular.ttf` (with `FRIZQT__`/`Expressway`/`Roboto`/`MORPHEUS`/`SKURRI` marked as non-CJK/Cyrillic/Hangul).
   - [options.lua](file:///home/sam/TacoTip-Gearscore-TBC/options.lua): Config `DEFAULTS`, `SafeSanitizeConfig`, final `/tacotip` / `/tt` slash router (`registerSlashCommands`), 4 Blizzard Settings canvas pages, and lazy `/tt` standalone dashboard (`createDashboard`).
   - [main.lua](file:///home/sam/TacoTip-Gearscore-TBC/main.lua) (`_G.TT`): Tooltip lifecycle (`onTooltipSetUnit`, `onTooltipShow`, `FriendsTooltip`, World Map pins), script font pass, secret guards, `FojjiCore` suppression, inspect cache integration, GS/Pawn memoization, PaperDoll/Inspect overlays + Forever stats footer & hover tooltips, 10-trophy Gear Progression engine, mover UI (`TacoTipDragButton`), and `/tt diag` diagnostics.

---

## 2. Client Families, Forever (`Camelot`) & Secrecy Boundaries

All WoW API verification references read-only `/home/sam/wow-ui-source` (`origin/classic_era`, `origin/classic_anniversary`, `origin/classic_titan`, `origin/forever`, `origin/live`) and `wago.tools`.

- **Classic Family (`11509`, `20506`, `38002`) vs Forever (`16001`) vs Retail (`120105`):**
  - **Forever Project ID:** `Blizzard_ProjectConstants/Camelot/ProjectConstants.lua` sets `WOW_PROJECT_CAMELOT = 18; WOW_PROJECT_ID = WOW_PROJECT_CAMELOT;` (**not** `MAINLINE`). `LibForeverInspector` tests `WOW_PROJECT_CAMELOT` first and uses `16000–19999` interface band as fallback.
  - **Talents Separation:** Classic/TBC/Titanforge use `GetNumTalentTabs`/`GetTalentInfo`/`GetActiveTalentGroup` (+ `C_SpecializationInfo.GetTalentInfo` query structs). Forever uses a separate `show_talents and isForever` branch reading Camelot `C_Traits` (`INSPECT_TRAIT_CONFIG_ID = -1`, `C_Traits.HasValidInspectData()`, `GetGroupDisplayInfoByTreeID`, `GetGroupCurrencyInfo`) + inactive spec via `C_SpecializationInfo.GetTalentInfo` when `GetNumSpecGroups() > 1`. Never cross classic `spec_table`/`talents_table` data into Forever.
  - **Zone Row (Forever):** Drawn on unit tooltips below Pawn/GS using `C_Map.GetBestMapForUnit(unit)` + `C_Map.GetMapInfo(mapID).name` and localized `ZONE`, strictly for `player`/`target`/`party`/`raid` (never nameplates, focus, pets, or target-of-target).
  - **Achievement Row:** Retail-only (`CI:IsRetail()`); disabled and suppressed on all other clients.
  - **Shaman Blue (`shaman_blue`):** Classic Era (`CI:IsClassic()`) only.
- **Forever Secrecy Rules (`main.lua` `isSecretValue` / `safeEquals` / `tooltipDataReadable` / `safeUnit*`):**
  - **`SecretArguments = "AllowedWhenUntainted"`:** Never pass possibly-secret tokens to `UnitExists`, `UnitIsPlayer`, `UnitIsConnected`, `UnitIsDeadOrGhost`, `UnitInParty`, `UnitGroupRolesAssigned`, `UnitIsSameServer`, `UnitDistanceSquared`, or `UnitFactionGroup`; route through `TT.safe*` / `LibForeverInspector` wrappers.
  - **Nil & Comparison Safety:** Check `type(v) == "nil"` **before** comparisons (`==`, `~=`, `<`, `>`, `%`). Strong guard: `local ok, isSec = pcall(issecretvalue, v); if (not ok or isSec == true) then return true end`.
  - **Tooltip Data Tables:** Guard every `data.*` access with `TT.tooltipDataReadable(data)` (`pcall(canaccesstable, data)` returning `true`).
  - **Power Bar (`StatusBar` Sink):** Validate `type(v) ~= "nil"` before passing values to `SetMinMaxValues`/`SetValue`.
  - **Native Loot Tooltip Passthrough:** Never add rows, re-font, cap width, or restyle Forever `GameTooltip:SetLootItem` / `SetLootRollItem`.
  - **Restricted Contexts:** Never register `COMBAT_LOG_EVENT_UNFILTERED`; local restriction testing uses non-persistent CVars `addonCombatRestrictionsForced`, `addonEncounterRestrictionsForced`, `addonMapRestrictionsForced`.

---

## 3. Tooltip Rendering, Fonts & Visual Lifecycle (`main.lua` & `textures.lua`)

- **Synchronous Visual Purge (`TT.clearTooltipVisuals`):** Fires on `OnHide`, `OnTooltipCleared`, `OnTooltipSetSpell`, `OnTooltipSetItem`, non-player `onTooltipShow`, and top of `onTooltipSetUnit`. Increments `tooltip._borderDeferralGen`, cancels deferred border timers, hides 2D portrait, calls `ClearModel()`/`Hide()` on `TacoTipPortrait3D`, hides/stops `TacoTipPowerBar`, clears custom bottom padding, and enforces `GameTooltip:EnableMouse(false)` in `GameTooltip_SetDefaultAnchor`.
- **Non-Latin (`ru` / `cn` / `ko` / `tw`) Glyph Support:**
  - `TT.ApplyFontIfNeeded` + `TT.ApplyTooltipFonts` inspect each FontString's live `GetFont()` (so Blizzard's C++ `SetText`/`AddLine`/`SetFontObject` resets back to `FRIZQT__.TTF` never bypass font updates), apply script fallback when `PickScriptFont` detects missing glyph coverage, and retry bundled fallback fonts if `SetFont` returns `false`.
  - Applied across `Wide` style (plus `TT:ApplyTooltipBottomPadding` & guarded `Show()` resize), `Normal`/`Compact`/`Mini` styles (`Target:` lines included), non-unit tooltips (`WhoList`, Guild/Social, spells), **`FriendsTooltip`** (`FriendsFrameTooltip_SetLine` hook + `OnShow` across `Header`/`NoteText`/`BroadcastText`/`LastOnline`/`OtherGameAccounts`/`GameAccount1..5Name/Info`/`GameAccountMany`), and **World Map unit pins** (`UnitPositionFrameMixin.UpdateUnitTooltips`, strictly skipped in `InCombatLockdown`, `IsInInstance`, `IsEncounterInProgress`, or any `C_RestrictedActions.IsAddOnRestrictionActive` restriction via `TT.CanStyleWorldMapTooltip`).
- **3D Portrait & Borders:** Base portrait `66 × 88` (`3:4` ratio, scale `0.5..2.0`, zoom `0.3..1.0`); `applyPortrait3DUnit` uses `CanSetUnit` + `Show()` before `ClearModel()`/`SetUnit()`, 20Hz `OnUpdate` parent-alpha sync, and post-layout edge-flip check in `OnShow`. Item tooltips support rarity borders via `TT:GetItemQualityBorderColor` (`tooltip_border_item_quality`), default border edge size `20px` (`4..48`).
- **Zero-Allocation Hot Path & FojjiCore:** Recycles line tables (`pooledLinesToAdd`, `pooledLineRecords`, `pooledPlayerText`). `blockFojjiCoreScoreRow()` suppresses duplicate score lines from `FojjiCore` / `FojjiCore_BiS` at source (`ADDON_LOADED`). Never override `GameTooltip.AddLine`/`AddDoubleLine` (causes Forever aura taint) and never re-anchor container item bag tooltips.

---

## 4. GearScore Engine, Inspection Queue & Persistent Cache

- **GearScore Formula Constants (`gearscore.lua`):**
  - Client `BRACKET_SIZE`: `200` (Classic Era / Forever), `400` (TBC Anniversary), `1000` (Titanforge / Retail); `MAX_SCORE = BRACKET_SIZE * 7`; `ITEM_BAND_SCALE = 11.25`.
  - Slot weights (`SlotMOD`): standalone 2H retains `2.000`, Titan's Grip applies `0.5` dampening only when dual-wielding, Hunter melee `0.3164x` / ranged `5.3224x`. Formula/bracket tables are frozen invariants.
- **Inspect Pipeline (`LibForeverInspector` + `main.lua`):**
  - **Range Policy:** Classic Era / TBC / Titanforge strictly require `CanInspect(unit)` (**1 arg only**) **AND** `CheckInteractDistance(unit, 1)` (`INSPECT_INTERACT_DISTANCE_INDEX = 1`, distance-first + learned range ceiling); Forever / Retail keep `CanInspect` **OR** `CheckInteractDistance`. Never replace `_G.PlaySound` (use `GetGameMessageInfo` in `UIErrorsMixin:TryDisplayMessage`).
  - **Priority & Recovery:** Priority 1 (`mouseover`/`target`/`focus`) ahead of lazy 4-role Priority 2 buckets (`Tank > Healer > DPS > None`) and time-sliced nameplate sweeps (`SCAN_SLICE_LIMIT = 20`); progressive failed-read retry backoffs (`1.5s → 3.0s → 4.0s` `CACHE_FAILED_BACKOFFS`), incomplete inspect gear stays `incomplete = true` (`GS_RETRY_MAX = 2.0s`) rather than committing partial GS, `PLAYER_REGEN_ENABLED`/`PLAYER_ENTERING_WORLD`/`PLAYER_FOCUS_CHANGED`/`InspectFrame_Show` hooks, and unit-level GS/Pawn memoization (`getGearScoreMemo`, `getPawnScoreMemo`).
  - **Cross-Reload Cache:** `LibForeverInspector` (`RECENT_CACHE_MAX_ENTRIES = 128`, `RECENT_CACHE_TTL = 1800s`) + `main.lua` (`SaveRecentInspectEntry`/`Cache`/`RestoreRecentInspectCache`) persist recent inspect snapshots in `TacoTipConfig.recentCache`.

---

## 5. Options, `/tt` Dashboard, Overlays, Progression & Diagnostics

- **Dashboard (`/tt`, `options.lua`):** `960x580` dark-themed UI (`DASH_CARD_W = 732`) with:
  - **Header Overall GS Bar (`_headerProg`):** Forever displays the calibrated 6-stage `TT.FOREVER_GS_SECTIONS` track (`Leveling 0–550` · `Pre-Raid 550–800` · `Tier 1 800–1000` · `Tier 2 1000–1180` · `Tier 3 1180–1300` · `??? 1300–1500+` dynamic cap), stage bands/dividers, peak marker, and up to `18` clickable snapshot pins.
  - **Tabs:** `General` (3×2 preset grid + Live Summary, combat hiding + modifier key, scale `50–200%`, `instant_fade`, minimap icon, language picker, CVar toggles), `Unit Content`, `Appearance & Bars` (flat font/bar/border/backdrop pickers, `openColorPicker` swatches, alpha/thickness), `Portrait & Icons`, `Positioning` (mutual exclusion between `custom_pos` [4-element literal contract] & `anchor_mouse`, `custom_anchor` corners, live coords), `Character & Inspect` (item-tooltip iLvl/GS/HunterScore + PaperDoll/Inspect X/Y offset nudgers), `Progression` (Hero card, 3-col Milestone Summary, 10 `TROPHY_DEFINITIONS` w/ `def.icon` & lock progress hints, 500-entry filterable Upgrade Chronicle, Snapshot/Export/Clear), optional `Extras` (P2P leaderboard), `Diagnostics` (bordered `/tt diag` viewer + Markdown export), `Community` (copyable URL cards + slash cheat-sheet), and `Reset Defaults` (footer Reset enforces 2-click confirmation).
  - **Engine Features:** `applySearch()` reflows matching rows from `y = 0`, hides empty sections/notices, updates scroll height; `createDashboardSlider` supports `SetValueSilently` & `SetDisabled`; `RefreshDependencyStates()` gates child options.
- **Character & Inspect Overlays (`main.lua`):** `InitCharacterFrame`/`RefreshCharacterFrame` & `InitInspectFrame`/`RefreshInspectFrame`; Forever renders `TT.foreverStatsFooter` cleanly inside `CharacterStatsPaneScrollBox` without mutating Blizzard's DataProvider/ScrollBox; `ShowCharacterStatTooltip` provides iLvl/GearScore breakdown tooltips on hover.
- **Progression & Diagnostics (`main.lua`):** `GetGearLevelStepSize()` (`25` Classic/Forever, `60` TBC, `100` WotLK, `150` Retail) ranks `Novice` → `Immortal Legend`; `/tt diag` collects live unit context, restriction snapshots, inspect/portrait rates, 15-entry `errorLog`/`warningLog` ring buffers, and `TT.LOAD_STAGE` fallback if `main.lua` fails to finish loading.
- **Slash Commands (`SLASH_TACOTIP1..7`):** `/tacotip`, `/tooltip`, `/tip`, `/tt`, `/gs`, `/gearscore`, `/taco` (`custom`/`move`, `default`, `save`, `reset`, `minimap`, `anchor`, `lb`/`ranks`, `diag`, `report`/`export`, `discord`, `help`).

---

## 6. Knowledge Base (`.omg/memory/`) & Active Rules (`.omg/rules/`)

- **Topic Files:** [architecture.md](file:///.omg/memory/architecture.md) · [blizzard_api_compat.md](file:///.omg/memory/blizzard_api_compat.md) · [dual_spec_inspect.md](file:///.omg/memory/dual_spec_inspect.md) · [tooltip_lifecycle.md](file:///.omg/memory/tooltip_lifecycle.md) · [options_ui_system.md](file:///.omg/memory/options_ui_system.md) · [localization_system.md](file:///.omg/memory/localization_system.md) · [verification_gates.md](file:///.omg/memory/verification_gates.md)
- **Rule Packs:** [01-zero-warning-luacheck.md](file:///.omg/rules/01-zero-warning-luacheck.md) · [02-framexml-api-discipline.md](file:///.omg/rules/02-framexml-api-discipline.md) · [03-non-unit-visual-isolation.md](file:///.omg/rules/03-non-unit-visual-isolation.md) · [04-dual-spec-inspect-handling.md](file:///.omg/rules/04-dual-spec-inspect-handling.md) · [05-locale-parity-standards.md](file:///.omg/rules/05-locale-parity-standards.md) · [06-version-release-bumping.md](file:///.omg/rules/06-version-release-bumping.md) · [07-core-invariants.md](file:///.omg/rules/07-core-invariants.md)

---

## 7. Lua 5.1 Constraints & Mandatory Verification Commands

- **Compiler Ceilings:** Keep `main.lua` under 200 file-scope locals and `onTooltipSetUnit` under 60 upvalues (`do ... end` helper groups attached to `TT.*`); keep `createDashboard()` tabs inside `do ... end`.
- **Verification Gates:**
  - `luacheck .` — **0 warnings / 0 errors** across all 70 files (no inline ignore comments).
  - `bash Tests/harness/run_all.sh` & `LUA=luajit bash Tests/harness/run_all.sh` — **75 / 75 passed, 0 failed** (plus `TacoTip_Extras/Tests/harness/run_all.sh` on `lua5.1`/`lua5.4`/`luajit`).
  - `wowlua_ls check . 2>&1 | grep -E "error"` — **0 errors** (`.wowluarc.json` declares `classic_era`, `classic`, `forever`, `retail`).
  - `bash Tools/verify_release.sh --worktree` (**42** runtime files) & `bash Tools/verify_release_extras.sh --worktree` (**29** runtime files) — both **PASS**. Never run state-changing git commands.
