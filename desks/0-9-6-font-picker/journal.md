# 0.9.6 — Font picker / media picker — Journal

## 2026-11-06 — Desk opened: 0.9.6 (font picker green rows + double dropdown)

- **Purpose:** fix the community report against TacoTip 0.9.5 on WoW Forever:
  clicking the font dropdown opens Blizzard's stock list and TacoTip's custom
  picker at the same time, and every font row is a solid green block. Bump the
  release to 0.9.6 and publish the operator's in-game test guide.
- **Scope:** TacoTip root add-on only. `TacoTip_Extras` out of scope (its own
  dropdowns do not use the custom media picker). No version bump for Extras.
- **Operator evidence:** user report on WoW Forever (interface 16001), TacoTip
  0.9.5; supplied a third-party rewrite as a hypothesis, not as an accepted
  patch.
- **Client truth read before editing:**
  - `origin/forever` / `origin/live`
    `Blizzard_SharedXML/Mainline/UIDropDownMenuTemplates.xml:146,190` — the
    arrow is a `DropDownToggleButton` inheriting
    `UIDropDownMenuButtonScriptTemplate`; activation is `OnMouseDown` via
    `DropDownMenuButtonMixin:OnMouseDown`
    (`UIDropDownMenuTemplates.lua:17-22`), and the template has no `OnClick`.
  - `origin/classic_era` / `classic_anniversary` / `classic_titan`
    `Blizzard_SharedXML/Classic/UIDropDownMenuTemplates.xml:220+` — the arrow is
    a plain `Button` with an XML `OnClick`; there is no `OnMouseDown`.
  - therefore the 0.9.5 override of only `OnClick` never removed the modern
    activation: one click fired the stock menu (mouse-down) and the custom
    picker (click).
  - `toggleMediaPicker` treated any slash/backslash value as a texture
    (`options.lua:1372-1397`), so `Fonts\\FRIZQT__.TTF` was passed to
    `Texture:SetTexture`; the client draws an unloadable texture as a solid
    green block.
- **Next step:** implement the minimal root-cause fix (one activation handler
  per client; texture preview opt-in; font rows preview the font), pin both
  behaviours in `options_test`, run all gates, bump 0.9.6, write the release
  notes and the operator test guide.

## 2026-11-06 — 0.9.6 media-picker fix implemented and gated

- **Worked on:** the two reported symptoms only. (1) `createOptionsDropdown`
  now replaces the activation handler the client actually installed
  (modern `OnMouseDown`, classic `OnClick`) and clears the other, so one
  click opens one list. (2) Texture preview is opt-in via
  `isTexturePicker` (status bar, border, background); the font dropdown sets
  `isFontPicker` and previews each row in its own face under `pcall`, with a
  default-font fallback and a reset between pickers. The stock template,
  width, anchors and spacing are untouched.
- **Scope decision:** the same audit found a latent third symptom — a disabled
  dropdown can still be opened by the frame body's `OnMouseDown`
  (`UIDropDownMenu_DisableDropDown` disables only the template arrow). Per
  the lane rule it is recorded in the bench audit and changelog and **not**
  edited; it is not part of the user report.
- **Deliberately not adopted:** the user-supplied flat-button rewrite. It
  restyles every dropdown and changes the options layout; the two reported
  symptoms are rooted in the activation and preview layers.
- **Pins:** `options_test` now models the real template arrow child and the
  per-family stock activation. 12 new checks; fixed tree **79/79**. Red proof:
  pre-fix **6/79** fail on Forever (handlers=2, stockOpened=1, green font
  texture, font preview nil) and **4/79** on Classic Era (green font texture,
  font preview nil); a texture-flag mutant **2/79**.
- **Docs:** 0.9.6 in TOC, both Lua fallbacks, README, CHANGELOG, AGENTS and
  both `load_test` version pins; README gains a 0.9.6 section and CHANGELOG a
  0.9.6 entry with the red proof.
- **Gates (2026-11-06):** `run_all` **72/72** on lua5.1, lua5.4 and luajit;
  `luacheck .` **0/0 in 88 files**; both `verify_release* --worktree`
  **PASS**; version consistency PASS.
- **Current state:** 0.9.6 tree is green and ready for the operator's in-game
  pass; no runtime files added; Extras untouched.
- **Next step:** operator opens each media dropdown on WoW Forever (font, bar,
  border, background) and confirms one list, readable font rows and working
  texture previews; then publish. The disabled-picker latent issue is a
  follow-up candidate, not part of this release.

## 2026-11-06 — [signal:done] 0.9.6 media-picker fix ready for in-game pass
- Both reported symptoms fixed and pinned; gates green; audit on the bench.

## 2026-11-07 — Power bar secret values + Retail-only achievements

- **Worked on:** (1) `main.lua` now shows the tooltip power bar when `UnitPowerMax` is a secret value (Forever/Live restricted units) and passes `UnitPowerMax`/`UnitPower` untouched to the status bar, whose `SetMinMaxValues`/`SetValue` accept secret bar values; non-secret clients keep the original `> 0` gate. (2) Achievements are Retail-only: `options.lua` enables the toggle only for `CI:IsRetail()`, and the `main.lua` render requires `isRetail`, so a saved true value cannot leak a row on Classic Era, TBC, Titanforge or Forever.
- **Global declaration:** `issecretvalue` is a read-only Blizzard global; declared in `.luacheckrc` `read_globals` (with the generated-doc citation). The add-on does not define or replace it.
- **API evidence:** `UnitPower`/`UnitPowerMax` are `SecretWhenUnitPowerRestricted`/`SecretWhenUnitPowerMaxRestricted` on `origin/forever` and `origin/live`; the status bar's `SetValue`/`SetMinMaxValues` are `AllowedWhenTainted` with `SecretAspect.BarValue`; `issecretvalue` is present on all five branches.
- **Pins/red proof:** tooltip_test +4. Pre-fix power gate 3/204 on Forever (including `attempt to compare number with table`); always-show mutant 1/204; pre-fix achievement row 1/204 on Forever, Retail 204/204; old achievement gate 1/65 on Forever and Titanforge, Retail 65/65. Fixed: 204/198/204 tooltip, 65/65 settings.
- **Gates (2026-11-07):** `run_all` **72/72** on lua5.1, lua5.4 and luajit; `luacheck .` **0/0 in 88 files**; both release verifiers **PASS**; version 0.9.6 consistent.
- **Current state:** 0.9.6 tree is green and ready for the operator's in-game pass; no runtime files added; Extras untouched.
- **Next step:** operator tests power bar on Forever + one Classic client and the Retail-only achievement toggle/row; then publish. The disabled-dropdown body-click remains the recorded follow-up.

## 2026-11-07 — [signal:done] 0.9.6 power bar and achievement gates ready for in-game pass
- Power bar secret pass-through and Retail-only achievement gate implemented, pinned and gated.
