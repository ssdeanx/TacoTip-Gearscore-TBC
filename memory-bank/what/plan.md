## Plan: TacoTip professional options UI

Refactor TacoTip’s legacy single-canvas settings screen into a professional parent category with child pages that still works on TBC Classic Anniversary clients. Preserve the current dual registration/opening logic, reuse the existing config surface first, and add the user-approved advanced positioning controls (anchor dropdown, numeric offset fields, sliders, clearer mover workflow). Ship new settings text in `enUS` first, relying on the existing `enUS.lua` fallback merge for other locales.
Approved by user on 2026-05-27 for implementation with the agreed scope: polished professional UI, parent category with subpanels, advanced positioning controls, and enUS-first localization.

**Steps**

1. **Phase 1 — Preserve and extend the settings shell**
   - Keep the current root registration strategy in `options.lua`: prefer `Settings.RegisterCanvasLayoutCategory` / `Settings.RegisterAddOnCategory` when available, otherwise fall back to `InterfaceOptions_AddCategory`.
   - Add child-page registration under the TacoTip parent entry.
     - Modern path: use `Settings.RegisterCanvasLayoutSubcategory` when available.
     - Legacy path: set `childFrame.parent = rootFrame.name` and register the child with `InterfaceOptions_AddCategory(childFrame)`.
   - Tighten `openOptionsPanel()` so opening the root page is reliable on both APIs and stays compatible with the legacy `InterfaceOptionsFrame_Show()` + `InterfaceOptionsFrame_OpenToCategory(...)` quirk. *Blocks Phases 3-5*
2. **Phase 2 — Convert `options.lua` into a reusable UI builder layer** *depends on 1*
   - Move widget creation out of the current one-shot absolute-position block inside `optionsFrame:SetScript("OnShow", ...)` into build-once helpers and page constructors.
   - Preserve and reuse the current logic helpers instead of re-implementing behavior: `getConfig()`, `resetCfg()`, `refreshLockPositionToggle()`, `updateInstantFadeState()`, `showTooltipMover()`, and `showExampleTooltip()`.
   - Introduce reusable builders for: section headers, scroll containers, checkboxes, radio groups, dropdowns, buttons, numeric edit boxes, sliders, and dependency-aware enable/disable wiring.
   - Keep globally named controls only where existing mover code depends on them, or replace those global-name assumptions deliberately in both `options.lua` and the consumer code. *Blocks Phases 3-5*
3. **Phase 3 — Create the parent category and child pages** *depends on 2*
   - Build a `TacoTip` root page that acts as the landing screen with addon title/version, a short description, quick actions, and either a preview surface or navigation summary.
   - Add child pages under the root parent:
     - `Tooltips` — unit tooltip appearance/content, item tooltip content, tooltip style.
     - `Positioning` — mouse anchoring, custom position, anchor selection, mover tools, instant fade, bar placement-related toggles.
     - `Character & Inspect` — character-frame/inspect overlays, lock state, GS/iLvl toggles, offset editing.
     - `Advanced` — combat suppression, CVars (`UberTooltips`, `chatClassColorOverride`), client-specific toggles, lower-priority power-user options.
   - Put long pages inside scroll frames so the interface scales better than the current fixed-position canvas.
4. **Phase 4 — Expose the hidden positioning surface with richer widgets** *depends on 2; can proceed in parallel with Phase 3 page content once the shell exists*
   - Add a dropdown for `custom_anchor` with the currently supported runtime values: `TOPLEFT`, `TOPRIGHT`, `BOTTOMLEFT`, `BOTTOMRIGHT`, and `CENTER`.
   - Add numeric edit boxes and sliders for the already-persisted offset keys:
     - `character_gs_offset_x`, `character_gs_offset_y`
     - `character_ilvl_offset_x`, `character_ilvl_offset_y`
     - `inspect_gs_offset_x`, `inspect_gs_offset_y`
     - `inspect_ilvl_offset_x`, `inspect_ilvl_offset_y`
   - Keep the mover button as the live/manual placement path; make sure mover actions, numeric edits, and sliders all refresh the same overlay state and stay synchronized.
   - Make the dependency rules obvious in the UI:
     - `custom_pos` vs `anchor_mouse`
     - `anchor_mouse_world` requiring mouse anchoring
     - `unlock_info_position` gating manual overlay movement
     - character/inspect offset controls only active when the related overlays are enabled.
5. **Phase 5 — Professionalize the existing feature surface instead of inventing too much new behavior** *depends on 3*
   - Re-group existing settings so the UI matches the runtime model more clearly:
     - tooltip appearance/content
     - item tooltip data
     - positioning/behavior
     - character/inspect overlays
     - advanced/client-specific controls
   - Reword help text/tooltips where the current labels undersell or misdescribe behavior, especially:
     - `hide_in_combat`
     - HunterScore conditions
     - the `show_gs_player` coupling with average item level in unit tooltips
     - WotLK-only achievement points.
   - Keep a live preview, but move it into a page/layout that does not crowd the controls.
6. **Phase 6 — Localization and string hygiene** *depends on 3-5*
   - Add the new page names, section headers, control labels, helper text, and positioning-field labels to `Locale/enUS.lua`.
   - Rely on the existing fallback merge in `Locale/enUS.lua` (`TACOTIP_LOCALE = TACOTIP_LOCALE or {}; defaults fill missing keys`) so non-English locales inherit English labels until a later translation pass.
   - Clean up the most visible locale inconsistencies that would look broken in the redesigned UI, but do not attempt a full all-locale translation pass in this iteration.
7. **Phase 7 — Documentation and maintenance alignment** *parallel with 6 after labels settle*
   - Update `README.md` so the published customization surface matches the new options pages and advanced positioning controls.
   - Update `CHANGELOG.md` and repo memory-bank notes so future maintenance work understands the new parent/subpanel UI structure and widget coverage.
8. **Phase 8 — Verification**
   - Run targeted diagnostics on every edited file after the refactor.
   - Verify in game on TBC Anniversary `20505` that TacoTip appears in the AddOns settings tree with the parent page and child pages.
   - Verify that opening the settings from slash/quick action reaches the correct parent page without legacy UI failures.
   - Verify that every page loads without Lua errors, the preview still updates, and reset/mover flows still work.
   - Verify that anchor dropdown changes, numeric offset edits, slider adjustments, and mover interactions all update the tooltip/character/inspect overlays and persist across reload.

**Relevant files**

- `c:\Program Files (x86)\World of Warcraft\_anniversary_\Interface\AddOns\TacoTip\options.lua` — primary refactor target; currently owns settings registration, widget creation, preview rendering, reset logic, mover button logic, and slash-driven panel opening.
- `c:\Program Files (x86)\World of Warcraft\_anniversary_\Interface\AddOns\TacoTip\main.lua` — consumes many of the settings this UI will expose, especially tooltip anchoring, health/power bars, custom position behavior, and character/inspect overlay refresh.
- `c:\Program Files (x86)\World of Warcraft\_anniversary_\Interface\AddOns\TacoTip\gearscore.lua` — relevant for mover integration, slash bootstrap history, and GearScore/overlay behavior referenced by settings.
- `c:\Program Files (x86)\World of Warcraft\_anniversary_\Interface\AddOns\TacoTip\pawn.lua` — relevant for Pawn-dependent controls and clearer UI messaging around optional Pawn integration.
- `c:\Program Files (x86)\World of Warcraft\_anniversary_\Interface\AddOns\TacoTip\Locale\enUS.lua` — add all new page labels, section headers, field labels, and help text here first.
- `c:\Program Files (x86)\World of Warcraft\_anniversary_\Interface\AddOns\TacoTip\README.md` — update feature and settings documentation once the new UI lands.
- `c:\Program Files (x86)\World of Warcraft\_anniversary_\Interface\AddOns\TacoTip\CHANGELOG.md` — record the UI overhaul and new customization controls.
- `c:\Program Files (x86)\World of Warcraft\_anniversary_\Interface\AddOns\TacoTip\memory-bank\activeContext.md` — update repo context after implementation.
- `c:\Program Files (x86)\World of Warcraft\_anniversary_\Interface\AddOns\TacoTip\memory-bank\progress.md` — update repo progress after implementation.

**Verification**

1. Run targeted `get_errors` on `options.lua`, `main.lua`, `gearscore.lua`, `pawn.lua`, `Locale/enUS.lua`, `README.md`, and `CHANGELOG.md` after the UI refactor.
2. In game, open the Blizzard AddOns/options UI and confirm `TacoTip` appears as a parent entry with child pages for the new structure.
3. Open TacoTip settings via slash/quick action and confirm the root page opens without `InterfaceOptions`/`Settings` API errors on the TBC Anniversary client.
4. Visit each child page and confirm controls initialize from `TacoTipConfig` correctly, including disabled-state dependencies.
5. Change the custom anchor dropdown, mover, numeric offset fields, and sliders; confirm both tooltip position and character/inspect overlay positions update immediately and persist after `/reload`.
6. Use Reset and mover flows to confirm `resetCfg()` still restores defaults and no longer throws `RefreshPosition`-related runtime errors.
7. Confirm the live preview still reflects tooltip-style/content changes and does not leak events when pages close.
8. Spot-check a non-English locale client or synthetic locale load to ensure new labels fall back to `enUS` rather than showing nil or blank text.

**Decisions**

- Approved scope: `Polish + advanced positioning`.
- Approved information architecture: `Parent category with subpanels`.
- Approved localization strategy: `enUS first`, using the existing fallback merge for untranslated locales.
- Included widget families for this pass: checkboxes, radio buttons, dropdowns, buttons, scroll frames, numeric edit boxes, and sliders.
- Deliberately excluded from this first pass: a full theme/color-customization system, broad new gameplay features, and a full all-locale translation sweep.
- Keep slash commands as shortcuts and recovery tools, not the primary configuration surface.

**Further Considerations**

1. Color pickers are a logical next step after this pass, but they should only be added once there are real persisted color settings to back them rather than adding placeholder UI.
2. If the modern `Settings` subcategory API proves inconsistent on the target client, the fallback should be to preserve the root page and internal page switching instead of breaking the AddOns entry entirely.
3. The safest implementation order is root registration/opening → reusable widget layer → child page migration → advanced positioning controls → string/docs cleanup.
