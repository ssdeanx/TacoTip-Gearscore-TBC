# Options UI System & `/tt` Standalone Dashboard

## 1. Dual Settings Architecture (`options.lua`)

TacoTip supports both Blizzard Settings panels and a full standalone `/tt` dashboard:

- **Blizzard Settings Canvases (`Settings.RegisterCanvasLayoutCategory` / legacy `InterfaceOptions_AddCategory` fallback):**
  1. `TacoTip` (Root: dashboard/diag launchers, style, core toggles, language selector, `UberTooltips`, chat class colors)
  2. `Tooltips` (Media pickers, 3D portrait controls, colors/alpha, border thickness)
  3. `Positioning` (Custom position vs mouse anchor mutual exclusion, mover anchor corner, instant fade, delay)
  4. `Character & Inspect` (PaperDoll/Inspect overlays, `progression_chat` / `progression_sound`, numeric X/Y offsets)
  - Canvas handlers (`OnRefresh`, `OnDefault`, `OnCommit`) are method fields (not `SetScript` slots) matching `Blizzard_SettingsPanel.lua`.

---

## 2. Standalone `/tt` Dashboard (`createDashboard`)

Built lazily on first open (`TacoTipDashboard`, `960x580`, `DASH_CARD_W = 732`), using `do ... end` blocks per tab to stay under Lua 5.1's 200-local limit:

- **Header Overall GearScore Bar (`_headerProg`):**
  - On Forever (`CI:IsForever()`): renders the calibrated 6-stage `TT.FOREVER_GS_SECTIONS` track (`Leveling 0–550` → `Pre-Raid 550–800` → `Tier 1 800–1000` → `Tier 2 1000–1180` → `Tier 3 1180–1300` → `??? 1300–1500+` with dynamic 200-GS cap scaling), stage bands/dividers, peak marker, clickable snapshot pins (`HEADER_PROG_MAX_PINS = 18`), and next-stage hover delta.
- **Navigation Tabs:** `General` (with 3×2 preset grid + Live Summary, scale, `instant_fade`, language/CVar controls), `Unit Content`, `Appearance & Bars` (flat media pickers & `openColorPicker` swatches), `Portrait & Icons`, `Positioning` (mutual exclusion + `custom_anchor` + saved coordinate readout), `Character & Inspect` (item-tooltip iLvl/GS/HunterScore + PaperDoll/Inspect X/Y offset nudgers), `Progression` (hero card, 3-column Milestone Summary, `def.icon` trophy tiles, filterable Upgrade Chronicle, Snapshot/Export/Clear), optional `Extras` (`TacoTip_Extras` P2P leaderboard + empty/search state), `Diagnostics` (`/tt diag`), `Community`, and `Reset Defaults` (footer reset also enforces two-click confirmation).
- **Search Reflow & Dependency Gating:** `applySearch()` compacts matching rows from `y = 0`, hides orphaned headers/static banners, and updates per-tab scroll heights; `createDashboardSlider` provides `SetValueSilently` and `SetDisabled`; `RefreshDependencyStates()` dims and annotates dependent controls.

---

## 3. Configuration Sanitization (`SafeSanitizeConfig`)

Clamps persisted `TacoTipConfig` values against `DEFAULTS`:
- `class_icon_size`: `8..32` (`20`), `tooltip_font_size`: `8..20` (`12`), `tooltip_border_edge_size`: `4..48` (`20`), `tooltip_scale` & `tooltip_portrait_scale`: `0.5..2` (`1`), `tooltip_portrait_zoom`: `0.3..1` (`0.7`), `tooltip_border_alpha` (`0.9`) & `tooltip_background_alpha` (`0.85`): `0..1`, `tip_style`: `1..5` (`2`), `tooltip_delay`: `0..5` (`0`), `tooltip_max_width`: `0..500` (`0`), plus Character/Inspect offset bounds and 4-element `custom_pos` preservation.
