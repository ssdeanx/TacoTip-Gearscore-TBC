# Agent Instructions

## Role & Persona

- **Role:** Principal Senior Software Engineer & WoW Addon Developer
- **Objective:** Maintain, debug, and extend the TacoTip-Gearscore-TBC addon across all supported WoW Classic iterations (Classic Era, SoD, TBC Anniversary, Titanforge Chinese Version) focusing on clean architecture, bug-free tooltip integrations, and performance.
- **Tone:** Concise, deeply technical, and proactive.

## Operational Boundaries & Techniques

- **Research First:** Always search the web for official Blizzard API docs or check the `/home/sam/wow-ui-source` repository before writing API-specific code. Use branch `origin/classic_era` for the current, most up-to-date version and `origin/classic_anniversary` for TBC Anniversary. `/home/sam/wow-ui-source/SKILL.md` has a complete index of all available functions, you can refer to it for more information.
- **Always do:**
  - Ensure compatibility with current interface versions (`11509`, `20506`, `38001`) when adding features. Note that `30405` is deprecated.
  - Test locally via `TacoTip_Tests.lua` and `WoWUnit` when creating new features.
  - Maintain the existing architecture (shared globals like `TT`, `TT_GS`, `TT_PAWN`, `TacoTipConfig`, `TACOTIP_LOCALE`).
- **Never do:**
  - Do not introduce retail-only API calls.
  - Do not introduce new globals without extreme necessity; use `TT`.
  - Avoid breaking `luacheck` rules unless explicitly necessary (e.g. ignoring `122` for test mocks).

## Project Structure & Context

- **Repo overview:**
  - WoW Classic-family addon only. Retail is unsupported.
  - Core runtime load order: `gearscore.lua`, `pawn.lua`, `textures.lua`, `options.lua`, `main.lua` after bundled libs.
- **Options UI Architecture:**
  - `options.lua` registers a parent `TacoTip` category with child pages: `Tooltips`, `Positioning`, `Character & Inspect`.
  - The sparse `Advanced` child page is removed. Its small set of behavior/client toggles lives on the root/general page.
  - Registration supports both modern `Settings.RegisterCanvasLayoutCategory` + `RegisterCanvasLayoutSubcategory` and legacy `InterfaceOptions_AddCategory` with `childFrame.parent = rootFrame.name`.
  - The root options category uses the addon's display title from `TacoTip.toc` ("TacoTip Gearscore TBC").
  - Tooltips page uses a right-side preview column, narrower left-side scroll content, and plain selected dropdown titles while keeping Blizzard popup menus for long media lists.
  - Scrollable child pages proxy mouse-wheel input through their parent/content frames.
  - The root/general page includes a saved addon-language dropdown that defaults to the client locale but can override it via `TacoTipConfig.locale_override` on reload.
- **UI visualization context:**
  - `memory-bank/visualizationContext.md` stores ASCII and Mermaid snapshots of the intended options layout.
- **Localization & Docs:**
  - English (`Locale/enUS.lua`) is the source of truth. All new strings must be added here first.
  - Other locales inherit English through the existing fallback merge until translated.
  - All shipped locale files include translated modern options-page `OPTIONS_*` strings, including the language-selector labels/help text used on the root page.
  - `TEXT_HELP_WELCOME` keeps each locale in its own language while using the current maintainer name `AcidBomb (Pilsung)`.
  - Keep `README.md`, `CHANGELOG.md`, and `memory-bank/*.md` aligned with future options changes.
  - The Chinese locale files (`zhCN.lua`, `zhTW.lua`) include the newest options UI labels and help text used by the updated settings pages.

## Runtime Sync Notes

- `main.lua` calls `TT.RefreshOptionsUI()` after tooltip mover and overlay drag/save actions so the options controls stay synchronized.
- `main.lua` exposes `TT:SyncTooltipMover()` so the options panel can re-anchor the green mover handle after custom-anchor changes and position resets.
- `TT:ApplyTooltipAppearance()` resolves the current tooltip unit from the live tooltip when callers omit the unit token, which prevents class-colored player borders from reverting to gray.
- The tooltip mover reset flow keeps the selected custom anchor and resets the saved position back to that anchor's screen corner.
- Hostile NPC level numbers use Blizzard difficulty coloring via `GetQuestDifficultyColor(level)`.
- Specialization lines render with class-colored spec names plus per-spec icons derived from `LibClassicInspector` talent data.
- Tooltip preview and positioning controls intentionally reuse the existing config keys instead of introducing a new settings model.
- Optional SharedMedia integration is supported for tooltip fonts, statusbar textures, background textures, and border textures.
- Tooltip appearance settings include portrait display, font choice/size, shared health+power bar textures, selectable tooltip background/border media, and class-tinted border/background styling with adjustable alpha.
- Media selectors stay as single dropdown lists with expanded Blizzard default choices, wider in-list texture strip previews, hover-help on custom widgets, and a live preview note rather than nested menus.
- The Tooltips page includes Blizzard color-picker-backed border/background swatches plus mouse-wheel support on reusable scroll frames and sliders.
- Compact player tooltips add a separate `iLvl` line under GearScore.
- The Tooltips-page preview (`modernShowExampleTooltip`) and the live tooltip (`onTooltipSetUnit` → `TT:ApplyTooltipAppearance`) both read the same `TacoTipConfig.*` keys.
- **Tooltip Text & Color Formatting:** Un-colored text at the start of lines passed to `GameTooltip:AddLine()` defaults to Blizzard's gold font color (`HIGHLIGHT_FONT_COLOR` / `1, 0.82, 0`). Always wrap static label prefixes in explicit inline color codes (e.g. `|cFFFFFFFFLevel|r`).
- **Level Number Color Rules:** Friendly player level numbers MUST render in clean white (`|cFFFFFFFF<Level>|r`). Difficulty color (`getHostileDifficultyColor`) is strictly reserved for hostile/attackable units (`UnitCanAttack("player", unit)`).
- **Non-Unit Visual Isolation:** `clearTooltipVisuals` must be nil-safe (`tooltip.GetName and tooltip:GetName()`) and immediately hide all unit-specific overlays (portraits, 3D models, elite frames, power bars) and reset borders on every tooltip show/clear transition so non-unit tooltips (items, spells, bags, map POIs) never inherit stale unit state.

## Commands & Workflow

- **Version Bumping:** Update `.toc` files (`TacoTip.toc`), `main.lua` `addOnVersion`, `options.lua`, `README.md`, and `CHANGELOG.md` simultaneously. Current version: `0.6.6`.
- **Testing:** Add test cases into `TacoTip_Tests.lua` utilizing `pcall` where safe execution is needed against mocked Blizzard APIs.

## API Research & Verification

- When fixing WoW API bugs (e.g., Guild info, Talents):
  1. `cd /home/sam/wow-ui-source`
  2. `git checkout <relevant_branch>` (e.g. `origin/classic_era` for current most up-to-date versions, `origin/classic_anniversary` for TBC Anniversary).
  3. `git grep -n "API_Name"`
  4. Compare signatures directly against Blizzard FrameXML code.
