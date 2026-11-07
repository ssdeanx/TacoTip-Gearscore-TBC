# TacoTip 0.9.6 — media picker audit (2026-11-06)

**Scope:** TacoTip root add-on, 0.9.5 working tree. Community report from WoW
Forever (interface 16001). `TacoTip_Extras` is a separate add-on and was not
edited.

**Verdict:** both reported symptoms are confirmed from the client source and
the add-on code, reproduced in the offline harness, and fixed at the root in
0.9.6. The supplied third-party flat-button rewrite was assessed and not
adopted. In-game confirmation is the operator's next step.

## Findings

### 1. Two lists from one click — VERIFIED (modern pair only)

- The add-on keeps Blizzard's `UIDropDownMenuTemplate` for the frame, text and
  arrow, but draws its own picker; it never wants the stock menu.
- On `origin/forever` and `origin/live`
  (`Interface/AddOns/Blizzard_SharedXML/Mainline/UIDropDownMenuTemplates.xml:138-145,190`)
  the arrow is a `DropDownToggleButton` inheriting
  `UIDropDownMenuButtonScriptTemplate`; activation is
  `DropDownMenuButtonMixin:OnMouseDown`
  (`UIDropDownMenuTemplates.lua:17-22`). The template declares no `OnClick`.
- On `classic_era` / `classic_anniversary` / `classic_titan`
  (`Interface/AddOns/Blizzard_SharedXML/Classic/UIDropDownMenuTemplates.xml:220+`)
  the arrow is a plain `Button` with an XML `OnClick` and no `OnMouseDown`.
- 0.9.5 replaced only `OnClick` (`options.lua` `createOptionsDropdown`), so on
  Forever/Retail the stock menu opened on mouse-down and the custom picker
  opened on click. Classic was already single-path in shape.

### 2. Solid green font rows — VERIFIED (all five families)

- Font choices are file paths (`Fonts\FRIZQT__.TTF`); `toggleMediaPicker`
  treated any value containing `\` or `/` as a texture and passed the font
  file to `Texture:SetTexture`.
- The reported green block is the client's rendering of an unloadable texture.
- The same heuristic was not type-aware: any future path-valued non-texture
  list would have hit it. Preview is now opt-in per dropdown.

### 3. A disabled dropdown can still open its picker — VERIFIED, NOT EDITED

- `UIDropDownMenu_DisableDropDown` disables the template arrow, but the frame
  body's `OnMouseDown` is the add-on's handler and does not consult the
  disabled state.
- This is an unreported second symptom; per the lane rule it is recorded here
  and in the changelog and left for a follow-up. It is not touched by 0.9.6.

### 4. The supplied rewrite — ASSESSED, NOT ADOPTED

- The user-supplied patch deletes the template, adds a flat button and a
  custom popup, and changes the layout offsets. That restyles every dropdown
  (style, language, guild rank, custom anchor) on every client and changes
  options spacing.
- The two reported symptoms are fully addressed at the activation and preview
  layers. Keeping the template preserves the player-visible frame, width,
  anchors, spacing and the `SetValues` / `SetValue` / `SetDisabled` contract.

## Change set (root add-on)

- `options.lua` — replace the template arrow's installed activation handler
  (`OnMouseDown` modern / `OnClick` classic) and clear the other; texture
  preview is opt-in via `isTexturePicker`; the font list sets `isFontPicker`
  and previews each row with `SetFont` under `pcall`, falling back to
  `GameFontHighlightSmall`; row fonts reset between pickers.
- Version 0.9.6 in `TacoTip.toc`, the `main.lua` / `options.lua` fallbacks,
  README frontmatter, CHANGELOG, AGENTS.md and both `load_test.lua` pins.
- No drop-down template removal, no width/anchor/spacing change, no
  saved-variable change, no Extras edit, no new runtime file.

## Pins and red proof — `Tests/harness/options_test.lua`

The mock now models the real template arrow child and the client-family
activation (`OnMouseDown` on project 1 = Forever/Retail; `OnClick` on
2/5/11 = Classic Era/TBC/Titanforge). Twelve new checks:

1. the font dropdown is found;
2. it declares `isFontPicker`;
3. the status-bar dropdown is found;
4. it declares `isTexturePicker`;
5. the arrow exposes exactly one activation handler;
6. one click opens no stock menu;
7. one click opens the custom picker;
8. the font picker opens a row for its first choice;
9. a font row is not painted with the font path;
10. a font row previews its own face;
11. the status-bar row under test exists;
12. a real status-bar texture still paints its row.

Red proof:

- pre-fix `options.lua`: **6/79 FAILED** on Forever — `handlers=2`,
  `stockOpened=1`, `texture=Fonts\2002.TTF`, font preview nil, plus the two
  preview-kind flags.
- pre-fix `options.lua`: **4/79 FAILED** on Classic Era — the two flags, the
  green font texture, and the missing font preview (no double-open there).
- a mutant that drops the status-bar texture flag: **2/79 FAILED**
  (`texture=Interface\Buttons\WHITE8X8`).
- fixed tree: **79/79 PASS** on Forever and Classic Era.

## Gates — 2026-11-06

- `bash Tests/harness/run_all.sh`: **72/72**, on lua5.1, lua5.4 and luajit.
- `luacheck .`: **0 warnings / 0 errors in 88 files**.
- `bash Tools/verify_release.sh --worktree`: **PASS** (27 files).
- `bash Tools/verify_release_extras.sh --worktree`: **PASS** (29 files).
- In-game verification: **pending**; the operator's Forever observation is the
  top rung.

## Operator in-game test (WoW Forever)

1. Open TacoTip options → Tooltips.
2. Click the **Tooltip font** arrow once: only one list should open.
3. Confirm every row is readable text (each row in its own face), not a green
   block; hover/click a font row and confirm the tooltip font changes.
4. Open **Health & power bar texture**, **Tooltip border texture** and
   **Tooltip background texture**: one list each, previews still visible.
5. Repeat on a Classic client (Era/TBC/Titanforge) to confirm the list still
   opens exactly once.

## Not changed

- `custom_pos`, `custom_anchor`, the mover, the tooltip pipeline, the
  FojjiCore row block, the inspect range gate, the GearScore formula, the
  saved-variable shapes, `CanInspect` arity, and every locale string.
- `TacoTip_Extras` (separate add-on, its own version and release verifier).
