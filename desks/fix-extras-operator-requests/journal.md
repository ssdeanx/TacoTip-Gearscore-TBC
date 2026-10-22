# Fix Extras Operator Requests — Journal

## 2026-10-20 — Desk opened
- **Purpose:** Two operator-requested changes to TacoTip_Extras only, live from a Classic Era test session: (1) the default tooltip display mode becomes Detailed instead of Compact; (2) a "Shaman Blue" control so the Extras' class name renders blue on Classic Era (whose client Shaman colour is pink).
- **Scope:** `TacoTip_Extras/{Core,Tooltips,Frames,RankBrowser,Options}.lua`, `TacoTip_Extras/Locale/*.lua` (all 11), `TacoTip_Extras/Tests/harness/*.lua` (pins only), `TacoTip_Extras/CHANGELOG.md`, `TacoTip_Extras/README.md`. NOT the main add-on, NOT any `.toc`, NOT `bench/`, NOT other desks. No commit, no staging.
- **Baseline (VERIFIED):** `bash TacoTip_Extras/Tests/harness/run_all.sh` = 42/42 on lua5.1/5.4/luajit; `cd TacoTip_Extras && luacheck .` = 0/0 in 26 files; `bash Tools/verify_release_extras.sh` = PASS.
- **Next step:** Change the default in `Core.lua:233`, add the Shaman-blue resolver to `Core.lua`, consult it from the three Extras class-colour sites, add the option + locales, pin both items in the harness, update CHANGELOG/README.

## Facts established this session (VERIFIED)

- **No explicit-set marker exists.** `TacoTipExtrasDB.settings.tooltip.mode` is a plain
  string (`Core.lua:232-234`). Nothing records whether the user picked it, so an
  untouched old default and an explicit user choice are indistinguishable.
  Per the task rule, therefore: **do NOT migrate a saved mode**; report the
  operator's reset path instead.
- **A schema bump is NOT a migration lever.** `Core.lua:317-330` treats
  `schema > 2` as a FUTURE schema and force-sets `equipmentDisplay.mode =
  "Disabled"`. Bumping to 3 would break the equipment windows.
- **`Core.ResetSettings()` (`Core.lua:426-438`) is the operator's reset path**:
  it wipes the settings table and re-normalizes, so the mode becomes the new
  default.
- **Client source (VERIFIED, `/home/sam/wow-ui-source`):**
  - Classic Era: `Interface/AddOns/Blizzard_SharedXML/Vanilla/ClassColors.lua:9`
    → `SHAMAN = CreateColor(0.96, 0.55, 0.73)` (PINK). Loaded via
    `Blizzard_SharedXML_Vanilla.toc:17`.
  - TBC / Wrath: `Interface/AddOns/Blizzard_SharedXML/TBC/ClassColors.lua:9`
    → `SHAMAN = CreateColor(0.0, 0.44, 0.87)` (BLUE — identical to the main
    add-on's `SHAMAN_BLUE_COLOR`, `main.lua:552`).
- **Main add-on's rule:** `main.lua:561` — `class == "SHAMAN" and (not
  TacoTipConfig or TacoTipConfig.shaman_blue ~= false)`. Default `true` at
  `options.lua:150`.
- **The three Extras class-colour sites:** `Tooltips.lua:451-460`
  (`playerClassColor`), `Frames.lua:272-281` (`classColor`), and
  `RankBrowser.lua:244-270` (`getClassColor`). The browser's hard fallback
  table already carries the blue (`RankBrowser.lua:103`), but it is only
  reached when neither `CUSTOM_CLASS_COLORS` nor `RAID_CLASS_COLORS` holds the
  class — on Classic Era `RAID_CLASS_COLORS.SHAMAN` exists, so the row is pink.
- **The Detailed-mode class name is class-coloured** (`Tooltips.lua:781-799`):
  Compact swaps the name for the 14px class icon with no tint; Detailed and
  Minimal keep the name in its class colour. That is the operator's report.

## 2026-10-20 — Both items implemented, pinned and validated

- **Worked on:** ITEM 1 (default tooltip mode Detailed) and ITEM 2 (Shaman Blue
  for the Extras) — TacoTip_Extras only.
- **Current state:** DONE and validated. All four commands green (Extras
  harness 42/42 on lua5.1/5.4/luajit, luacheck 0/0 in 26 files,
  `verify_release_extras.sh` PASS, main harness 70/70). No commit, no staging.
- **Next step:** operator to re-test in a Classic Era session. Two things they
  must do by hand: (1) on an EXISTING install the saved tooltip mode is kept
  on purpose, so to SEE Detailed they use the Options page — the "Tooltip
  mode" dropdown, or the "Reset enhancer settings" button (which restores
  every default, Shaman Blue included); (2) if they turned Shaman Blue off in
  TacoTip, the Extras stay pink — that is the cross-add-on veto working.

### What changed, per item

**ITEM 1 — default tooltip mode.**
- `Core.lua`: new `DEFAULT_TOOLTIP_MODE = "Detailed"` constant plus a long
  comment on why there is NO migration; `normalizeSettings` now assigns that
  constant instead of the literal `"Compact"`.
- The branch only fires when the mode is MISSING or invalid, so it is a
  fresh-install default and nothing else.
- **No migration, deliberately.** The settings table records no "the user set
  this" marker, so a saved `"Compact"` cannot be told apart from an untouched
  old default. Overwriting it would destroy a deliberate choice. A schema bump
  is NOT a safe migration lever either: `initializeDatabase` treats
  `schema > 2` as a future schema and force-sets
  `equipmentDisplay.mode = "Disabled"`, which would break the character and
  inspect windows. The saved mode is therefore left exactly as the user left
  it.
- **The operator's path to Detailed on an existing install:** TacoTip Extras
  Options page → "Tooltip mode" dropdown → Detailed; or "Reset enhancer
  settings", which wipes the settings table and re-normalizes, so every
  default (including Detailed) comes back.

**ITEM 2 — Shaman Blue.**
- `Core.lua`: `SHAMAN_BLUE_COLOR = { r = 0.0, g = 0.44, b = 0.87 }` (the main
  add-on's numbers), `Core.IsShamanBlueEnabled()` and
  `Core.GetClassColorOverride(classToken)`. ONE resolver.
- The effective value is ON only if BOTH the Extras' own setting AND the main
  add-on's allow it. The main add-on's value is read DEFENSIVELY: only an
  explicit boolean `false` suppresses the rule; an absent `TacoTipConfig`, a
  nil value and a non-boolean all degrade to the Extras' own setting.
- `normalizeSettings` adds `defaultBoolean(runtime, "shamanBlue", true)` —
  top level of the settings table, not under `tooltip`, because the class
  colour is painted in three surfaces.
- The three call sites consult the resolver FIRST, before their own colour
  chains: `Tooltips.playerClassColor`, `Frames.classColor`,
  `RankBrowser.getClassColor`.
- `Options.lua`: a "Shaman Blue" checkbox at (290, -318) on the Tooltip page,
  the `ShamanBlue` HELP entry with two lines, and a `Refresh` that shows the
  setting in effect. Toggling it repaints all three surfaces (tooltips +
  frames via `applyAllSettings`, the browser rows via `RankBrowser.RebuildUI`).
  The tooltip's own change gate picks the colour change up automatically,
  because it already compares `classRed/classGreen/classBlue`.
- **The checkbox shows the Extras' OWN setting**, not the effective value:
  the help text says plainly that TacoTip's own setting applies too and can
  turn the blue off. A control that rendered the effective value would refuse
  to stay ticked when TacoTip vetoes, which reads as a broken checkbox.

### Locale

All eleven Extras locale files carry `OPT_SHAMAN_BLUE`, `HELP_SHAMANBLUE_HEADING`,
`HELP_SHAMANBLUE_1` and `HELP_SHAMANBLUE_2` — properly translated, no English
fallback left in any language. The option NAME and the base description are
the main add-on's own translations (`Locale/*.lua`: `OPTIONS_SHAMAN_BLUE` /
`OPTIONS_SHAMAN_BLUE_DESC`), so the two add-ons name the option the same way.
enUS carries the file's per-key fallback comment.

### Pins added (and their revert reds)

`TacoTip_Extras/Tests/harness/load_test.lua` (556 checks), plus four pins in
`rankbrowser_test.lua`. The dropdown and checkbox mocks were made OBSERVABLE
(`UIDropDownMenu_SetSelectedValue`/`GetSelectedValue` record, `SetChecked`
records) so "the control shows the setting in effect" is an assertion about
something real rather than about nothing.

- ITEM1-a default reverted to Compact → `default tooltip mode is Detailed`,
  `a missing saved tooltip mode resolves to the Detailed default`,
  `the tooltip-mode control shows the effective mode (Detailed)`,
  `the tooltip-mode control labels itself with the effective mode`.
- ITEM1-b a migration overriding a saved Compact → `an explicitly saved
  tooltip mode is preserved (no migration overrides it)`.
- ITEM1-c the control showing a hardcoded Compact → the two dropdown pins.
- ITEM2-a the tooltip stops consulting the resolver → the rendered blue pin
  and the source pin.
- ITEM2-b the browser stops consulting the resolver → the rendered row pins.
- ITEM2-c the character/inspect frame stops consulting the resolver → the
  source pin for `Frames.lua`.
- ITEM2-d the main add-on's veto ignored → `an explicit false in the main
  add-on suppresses the rule` and both veto pins.
- ITEM2-e the default off instead of on → the default pins.
- ITEM2-f the setting dropped instead of persisted → the reload-survival pin.
- ITEM2-g the option removed from the panel → `the Shaman Blue option exists
  on the panel`.
- ITEM2-h the control showing a hardcoded value → `the Shaman Blue control
  shows the setting in effect (off when off)`.
- ITEM2-i the option label stops coming from the locale → `the Shaman Blue
  option is labelled with the localized heading`.

### Two harness traps hit and fixed (worth remembering)

- `row and colorOf(row.nameText) or nil` truncates a MULTIPLE return to ONE
  value, so the green and blue read nil. `colorOf` was called on its own line
  instead. The harness's own comments warn about this family.
- `loadFile("Core.lua")` returns nil — Core.lua publishes itself on the
  namespace and returns nothing. The module is read back from
  `namespace.Core`.

### Not done, deliberately

- The character/inspect frame's rendered text is NOT pinned directly: its rows
  are anonymous FontStrings the mock does not expose. What IS pinned is that
  `Frames.lua` calls the one shared resolver and carries no second copy of the
  colour. The two surfaces that CAN be rendered — the tooltip and the
  leaderboard row — are pinned on their rendered output.

## 2026-10-20 — [signal:done] Both items shipped to the operator's session

- **Worked on:** closed the desk's workstream. Item 1 (Detailed default) and
  item 2 (Shaman Blue for the Extras) are implemented, pinned, revert-proven
  and validated; the signal is written to
  `.signals/2026-10-20T10-05-00Z.json`.
- **Current state:** four commands green — Extras harness 42/42 on lua5.1,
  lua5.4 and luajit; `luacheck .` 0 warnings / 0 errors in 26 files;
  `verify_release_extras.sh` PASS; main harness 70/70. No commit, no staging.
- **Next step:** the operator re-tests in a Classic Era session. On an
  EXISTING install the saved tooltip mode is preserved on purpose, so to SEE
  Detailed they must use the Options page ("Tooltip mode" dropdown, or the
  "Reset enhancer settings" button). If they turned Shaman Blue off in
  TacoTip, the Extras stay pink — the cross-add-on veto working as intended.

## 2026-10-20 — Items 3 and 4 folded in (gear panel backdrop, bigger window)

- **Worked on:** ITEM 3 (the gear panel rendered transparent) and ITEM 4 (the
  leaderboard window too small, the sort readout sitting on the column
  headers). Same desk, same validation bar, same revert-to-fail bar.
- **Current state:** DONE. All four commands green again (Extras harness
  42/42; luacheck 0/0 in 26 files; `verify_release_extras.sh` PASS; main
  harness 70/70). Extras harness is now 560 checks in `load_test.lua` and 304
  in `rankbrowser_test.lua`. No commit, no staging.
- **Next step:** the operator re-tests in a Classic Era session — open a
  leaderboard row and read the gear panel (it must have a background now), and
  open the leaderboard (it must be bigger, and "Sorted by GEARSCORE" must have
  a line of its own).

### ITEM 3 — the gear panel is opaque again

**Root cause, confirmed in the CLIENT SOURCE (not from the mock):** the gear
panel was created as a PLAIN frame — `g.CreateFrame("Frame",
"TacoTipGearPanel", parent)`, no template — so in the real client it had no
`SetBackdrop` at all and the `if f.SetBackdrop then` guard SKIPPED the
backdrop. The panel rendered transparent.

VERIFIED, all five branches (`/home/sam/wow-ui-source`):
- `Interface/AddOns/Blizzard_SharedXML/Backdrop.xml:5` —
  `<Frame name="BackdropTemplate" mixin="BackdropTemplateMixin" virtual="true">`
- `Interface/AddOns/Blizzard_SharedXML/Backdrop.lua:336 / :354 / :406` —
  `SetBackdrop` / `GetBackdrop` / `SetBackdropColor`.

**A correction to the brief's premise, recorded because it changes the mock:**
the brief says "the browser frame is fine: ButtonFrameTemplate gives it one".
ButtonFrameTemplate does **NOT** carry the backdrop API. It inherits
`PortraitFrameTemplate` -> `PortraitFrameTemplateNoCloseButton` ->
`PortraitFrameBaseTemplate`, whose mixins are `PortraitFrameMixin` /
`PortraitFrameTemplateMixin` (`SharedUIPanelTemplates.xml:387`, `:440`,
`:674`) — it paints its own background TEXTURE instead. The browser frame is
therefore NOT transparent (the template's own background covers it), but the
`if f.SetBackdrop then` guard around the DialogFrame backdrop skips there too.
The browser is left exactly as it is: it looks right, and changing its chrome
is out of scope. What the correction changes is the MOCK: `ButtonFrameTemplate`
must not carry the backdrop API either, or the mock would keep saying yes to
something the client says no to.

**Production (`RankBrowser.lua`):**
- `:1373` `createBackdropFrame(name, parent)` — creates with the
  `BackdropTemplate`, falls back to a plain frame, and then MIXES IN
  `BackdropTemplateMixin` by hand if the template was unavailable. That is the
  same shape the main add-on's tooltip path uses (`main.lua`
  `getOrCreateBackdropFrame`).
- `:1406` the gear panel is created through it. The existing
  `SetBackdrop(...)` + `SetBackdropColor(0, 0, 0, PANEL_BACKDROP_ALPHA)` now
  actually runs, so the panel gets the same dark background and border as the
  window, at the same 0.9 opacity. Its 400x470 size is untouched.

**Harness fidelity gap closed:**
- `rankbrowser_test.lua:156` `BACKDROP_TEMPLATES = { BackdropTemplate = true }`
  and `:376` the backdrop methods are copied onto a frame ONLY when its
  template confers them; `:384` records `region.__absent` otherwise.
- `load_test.lua:646` the same table, and `:669` the same per-frame decision;
  the `__index` at `:697` consults `__absent` FIRST (via `rawget`) and does
  NOT count an absent key as a method miss — probing a method the client does
  not have is the correct guarded behaviour.
- The mock's `SetPoint` now RECORDS the anchor, so "the sort readout has a
  band of its own" is a statement about geometry instead of a guess.

**An existing harness assertion had to be corrected, not deleted.** It read
"both panels paint an explicit backdrop color" and PASSED — on the mock's own
stub. With the absence modelled it goes red for the BROWSER frame, which
genuinely has no backdrop API. The truth is now pinned: the gear panel paints
an explicit black 0.9 backdrop, and the browser frame has no backdrop API
because `ButtonFrameTemplate` supplies its own background.

### ITEM 4 — a bigger window, and a band for the sort readout

**The collision, measured.** The readout sat at `rowTop() + 26`; the sortable
column-header buttons sit at `headerTop() + 4`. With the old constants
(`ROW_TOP` -104, `HEADER_TOP` -82) those are the SAME y (-78) — the readout
was drawn straight through the header row — and the stat strip, two pixels
above, was crowded against it.

**Production (`RankBrowser.lua`):**
- `:26-28` `FRAME_WIDTH` 720 -> 860, `FRAME_HEIGHT` 520 -> 560,
  `ROW_WIDTH` 660 -> 800.
- `:44-48` the panel's vertical layout is now a set of named BANDS:
  control row -46, stat strip -70, sort hint -90, headers -110, rows -134.
  `:263` `statTop()` and `:269` `hintTop()` resolve them (with `chromePad`).
- `:2133` the stat strip uses `statTop()`; `:2334` the readout uses
  `hintTop()` — its own band, clear of both neighbours; `:2337` the readout is
  exposed on the frame (`f.sortHint`), matching the file's existing
  convention for `statStrip` / `footerText` / `progressBar`.
- The columns are wider to use the extra width, and the row's ICONS are now
  anchored to their COLUMN rather than to a fixed offset: `:1910`/`:1916` the
  spec icon to `specColumn.x - ICON_GAP`, `:1925`/`:1931` the class icon to
  `nameColumn.x - ICON_GAP`, `:1961` the YOU tag to `ROW_WIDTH - 36`.
  **This fixed a pre-existing overlap:** the spec icon used to be anchored
  246px from the row's left while the spec TEXT began at 232, so the icon was
  drawn ON TOP of the first characters of the spec name.

### Revert reds (18 proofs, all on a copy of the tree)

ITEM1-a/b/c, ITEM2-a..i as recorded above, plus:
- ITEM3-a the gear panel created as a plain frame again -> `the gear panel is
  backdrop-capable`, `the gear panel's backdrop is applied`, `the gear
  panel's backdrop is opaque black (0.9 alpha)`, `the gear panel paints an
  explicit backdrop color`.
- ITEM3-b the backdrop colour left at the default -> the two colour pins.
- ITEM3-c the mock hands every frame the backdrop API again -> `a plain frame
  in this environment has no SetBackdrop`, `the plain frame records the
  backdrop API as absent`, `the browser frame has no backdrop API`.
- ITEM4-a the frame back to 720x520 -> `the leaderboard frame is larger than
  it was (720x520)`.
- ITEM4-b the readout anchored back on the header row -> `the sort readout
  sits above the column headers`, `the sort readout's band clears the column
  headers by a text line` (gap -2).
- ITEM4-c the readout sharing the stat strip's band -> `the sort readout sits
  below the stat strip, not on it`, `the sort readout's band clears the stat
  strip by a text line` (gap 0).
- ITEM4-d the gear panel stretched with the window -> `the gear panel keeps
  its own 400x470 size`.
- ITEM4-e/f the spec / class icon anchored on top of its text -> `the spec
  icon is anchored clear of the spec text`, `the class icon is anchored clear
  of the player name`.

The restored copy is green again: 42/42.

### A pin that was too weak and had to be strengthened

The first version of the band pin only asserted "the readout is above the
headers" and "no button shares the readout's y". That caught the ORIGINAL
exact collision but not a two-pixel gap — which is just as unreadable, and is
what `rowTop() + 26` produces against the new constants. The pin now requires
a full text line (12px) of clearance from BOTH the headers and the stat
strip, and the revert proof shows the gap going to -2.

## 2026-10-20 — [signal:done] Items 3 and 4 shipped

- **Worked on:** closed the second workstream. Item 3 (the transparent gear
  panel) and Item 4 (the small leaderboard window and the sort readout on the
  column headers) are implemented, pinned, revert-proven and validated; the
  signal is written to `.signals/2026-10-20T12-40-00Z.json`.
- **Current state:** four commands green — Extras harness 42/42 on lua5.1,
  lua5.4 and luajit; `luacheck .` 0 warnings / 0 errors in 26 files;
  `verify_release_extras.sh` PASS; main harness 70/70. No commit, no staging.
- **Next step:** the operator re-tests in a Classic Era session — click a
  leaderboard row and read the gear panel (it must have a background now), and
  open the leaderboard (it must be bigger, and "Sorted by GEARSCORE" must have
  a line of its own, clear of the strip above and the headers below).

## 2026-10-20 — Item 5: the options page's two-column layout

- **Worked on:** ITEM 5 — the Extras options page: overlapping columns, the
  "Comfortable rows" control, and the alignment of the checkbox area.
- **Current state:** DONE. All four commands green (Extras harness 42/42;
  luacheck 0/0 in 26 files; `verify_release_extras.sh` PASS; main harness
  70/70). The Extras harness is now 569 checks in `load_test.lua` and 304 in
  `rankbrowser_test.lua`. No commit, no staging.
- **Next step:** the operator re-tests in a Classic Era session — open the
  Extras options page and check that the long "Restrict Potential,
  Completion, and warnings to level 70" label wraps inside its own column
  instead of running into the right-hand column, that every box in the right
  column is easy to click, and that "Comfortable rows" shows whether it is on.

### What the brief's stated root cause turned out to be

The brief said the hit rect is "expanded 240px to the RIGHT". **That part is
RIGHT, and it is worth saying why it was worth checking rather than assuming.**
The `SetHitRectInsets` argument order is `(left, right, top, bottom)` — NOT
`(left, top, right, bottom)`, which is the order the WoW wiki quotes and the
order I half-remembered. VERIFIED in the client source:

- `origin/classic_era` `Interface/AddOns/Blizzard_APIDocumentationGenerated/
  SimpleFrameAPIDocumentation.lua:1150-1153` — `{ Name = "left" },
  { Name = "right" }, { Name = "top" }, { Name = "bottom" }` (the same on
  `origin/live`).
- Blizzard's own calls use the SECOND argument as a right expansion:
  `origin/classic_era` `Interface/AddOns/Blizzard_Calendar/Classic/
  Blizzard_Calendar.lua:3799` —
  `self:SetHitRectInsets(0, -CalendarCreateEventAutoApproveCheckText:GetWidth(), 0, 0)`.

So `SetHitRectInsets(0, -500, 0, 0)` really did stretch every left-column
checkbox 500 pixels to the right, from x=16 to x=542, straight across the
right column at x=290. The right column's controls happened to be created
LATER, and a later sibling is drawn on top, so the clicks mostly worked — by
luck of creation order, not by design.

### The "grey box" — what the source says, and what it does not

**I could not reproduce a missing-texture cause, and I am not going to claim
one.** The operator's screenshot is not in the repo: the only PNGs are old
tooltip captures from 2026-10-16 (`TacoTip_Extras/1.png` .. `7.png`), and I
looked at them — none is the options page.

What the source DOES establish, on all five branches:

- `InterfaceOptionsCheckButtonTemplate` EXISTS, in
  `Interface/AddOns/Blizzard_FrameXML/DeprecatedTemplates.xml:34`
  (`classic_era`, `classic_anniversary`, `classic_titan`, `forever`, `live`),
  and `DeprecatedTemplates.xml` is in the TOC on all five.
- It inherits `OptionsBaseCheckButtonTemplate` (`DeprecatedTemplates.xml:5`)
  -> `UICheckButtonTemplate`
  (`Blizzard_SharedXML/Shared/Button/CheckButtonTemplates.xml:50`) ->
  `UICheckButtonArtTemplate`, whose `NormalTexture` is
  `Interface\Buttons\UI-CheckBox-Up`. That texture is one Blizzard's OWN
  Classic Era UI uses (`Blizzard_AchievementUI/Classic/
  Blizzard_AchievementUI.xml:196`), so it is present.
- **The MAIN add-on uses the same template** (`options.lua:1427`) and the
  operator has never complained about ITS check boxes. That is the strongest
  evidence available, and it exonerates the template.

So the template stays. The one measurable difference is that
`OptionsBaseCheckButtonTemplate` resizes the shared 32x32 template down to
26x26 (`<Size x="26" y="26"/>`), so the art is squashed by 19% — worth
knowing, not worth a page-wide re-flow on its own, and NOT a grey box.

**What the fix actually addresses is the only mechanism the source supports
for a box instead of a small check button: the hit rect.** A 500-pixel
expansion is a 500-pixel region, and the client draws the button's hover
highlight over the region the button answers for. Shrinking the expansion to
the label's own width is the fix that removes both the highlight swallowing
the neighbour and the click stealing it.

**And a real defect in the exact control the operator named:** the
"Comfortable rows" checkbox was the ONE control `Options.Refresh` never
`setChecked`. A profile that had the setting on came up with the box looking
off. Fixed.

### Production changes (`Options.lua`)

- `:706-717` the column geometry as named constants: `RIGHT_COLUMN_X` 290,
  `PANEL_CONTENT_RIGHT` 590, `CHECKBOX_SIZE` 26 (the size the client gives
  the check button, cited), `LABEL_GAP` 2.
- `:720` `columnLabelWidth(x)` — the width a label may use, derived from the
  column its control is in.
- `:727` `createCheckbox` — the label is capped to its column and wraps
  inside it; the hit rect is the LABEL's own width, capped at the column.
  The old flat `helpWidth` argument is gone from the signature and from every
  call site.
- `:878` `createEquipmentCheckbox` — the same rule, capped at the equipment
  panel's content width.
- `:1968` `Options.Refresh` syncs `controls.ComfortableRows`.
- **The "Open Server Leaderboard" callback was not touched** (the operator
  confirmed it works).

### Harness

- The mock now RECORDS geometry: `SetPoint` (`:790`), `SetSize`/`GetWidth`
  (`:811`), `SetHitRectInsets` (`:835`), `SetWordWrap` (`:848`), plus
  `__children` so a panel's children can be enumerated.
- `:667` `TEMPLATE_SIZES` — the check button's 26x26 comes from the client's
  template, so the mock reports the same geometry the client would.
- A FontString with no explicit width sizes itself to its text (`:811`),
  because that is why an uncapped label runs into the next column — and
  without it the "no label overflows" pin was VACUOUS (it passed on a
  zero-width label). The revert proof caught exactly that.

### Revert reds (5 more, all on a copy of the tree)

- ITEM5-a the hit rect is a flat 500px expansion again -> `no two checkbox hit
  rects overlap`, `no checkbox's clickable region reaches into the right
  column`.
- ITEM5-b the label loses its width cap -> `no checkbox label overflows into
  the next column`, `every checkbox label wraps inside its column`.
- ITEM5-c the label is capped but no longer wraps -> `every checkbox label
  wraps inside its column`.
- ITEM5-d the Comfortable rows sync removed -> `the Comfortable rows control
  shows its setting (on)`.
- ITEM5-e a checkbox uses a template the client does not define -> `every
  template the options page uses is one the client defines`.

All 23 revert proofs across items 1-5 were re-run against the final tree; the
restored copy is 42/42.

### Out of scope, found and reported

- **"Comfortable rows" has no locale key.** `HELP_COMFORTABLEROWS_HEADING`
  and `HELP_COMFORTABLEROWS_1` are missing from all ELEVEN locale files, so
  that control's label falls back to English on every non-English client. It
  is a pre-existing gap, not what the operator reported, and it is in the
  locale files rather than in ITEM 5's stated scope, so it is NOTED and not
  chased. The same is true of `HELP_COMFORTABLEROWS_*` in the help popup.

## 2026-10-20 — [signal:done] Item 5 shipped

- **Worked on:** closed the third workstream. Item 5 (the options page's
  two-column layout, the clickability of the right-hand column, and the
  "Comfortable rows" control) is implemented, pinned, revert-proven and
  validated; the signal is written to
  `.signals/2026-10-20T14-20-00Z.json`.
- **Current state:** four commands green — Extras harness 42/42 on lua5.1,
  lua5.4 and luajit; `luacheck .` 0 warnings / 0 errors in 26 files;
  `verify_release_extras.sh` PASS; main harness 70/70. No commit, no staging.
- **Next step:** the operator re-tests in a Classic Era session — open the
  Extras options page and check the long "Restrict Potential, Completion, and
  warnings to level 70" label wraps inside its own column, that every box in
  the right-hand column is easy to click, and that "Comfortable rows" shows
  whether it is on. If anything still paints as a box, a fresh screenshot of
  the page is the next piece of evidence — the source could not explain it.

## 2026-10-20 — Item 4 refined: a taller window and a band stack

- **Worked on:** the operator's refinement of ITEM 4 from the in-game screenshot:
  the leaderboard must get TALLER as well as wider, the text must be easy to
  read, and the content must lay out as a clean vertical stack with each
  band owning its own space.
- **Current state:** DONE. All four commands green (Extras harness 42/42;
  luacheck 0/0 in 26 files; `verify_release_extras.sh` PASS; main harness
  70/70). `rankbrowser_test.lua` is now 303 checks. No commit, no staging.
- **Next step:** the operator re-tests in a Classic Era session — open the
  leaderboard and check that the window is bigger in BOTH directions, that
  sixteen players show without scrolling, and that "Sorted by GEARSCORE", the
  summary strip, the column headers, the last row and the footer each sit in
  their own space with nothing drawn over anything else.

### The band stack

The layout is now a stack of BANDS, and the frame's height is the SUM of the
bands. The band offsets are derived from that sum by walking back up the same
stack, so the two are the same number by construction and a band can never be
given space another band already has.

```
  title      the window title
  filter     scope label, class filter, guild box, search box
  stat       the summary strip: pool size, top GS, average GS
  hint       the sort readout, on a line of its own
  header     the column headers
  table      the rows
  progress   the scan rail and its completion line
  footer     the standing line, Top / My Rank / Scan now
```

- `RankBrowser.lua:51-58` the band heights; `:61` the progress rail's height.
- `:294` `layoutBands(contentHeight, rowsBandHeight, titleBandHeight)` — walks
  the stack UP from the content height, so the tops and the height are the
  same number by construction.
- `:317` `applyBandLayout(frame)` — sizes the frame and fills the band tops.
  **It is its own function, not a block inside CreateUI:** Lua 5.1 caps a
  function at 60 upvalues and CreateUI is already at the ceiling, so the
  layout arithmetic lives here instead. That was found the hard way — the
  first attempt put six more locals in CreateUI and the file stopped loading
  with "function at line 2108 has more than 60 upvalues".
- `:340-381` the accessors: `bandY` for the top-anchored bands and
  `footerBottom` / `progressBottom` / `tableBottom` for the bottom-anchored
  ones, read from the other end of the same stack.
- `:22` `NUM_ROWS` 12 -> 16 (the operator asked for more height "so the list
  shows more players without scrolling"); `:27-28` `FRAME_WIDTH` 900,
  `ROW_WIDTH` 820, with the name and spec columns widened to use it.
- The gear panel keeps its own 400x470 (the operator confirmed the panel
  opening over the browser is fine).

### The harness's NUM_ROWS was REVISITED, deliberately

`rankbrowser_test.lua` carries the comment "if the browser grows or shrinks
its visible page, this test must be revisited, not silently re-tuned to
whatever the new value happens to be". It was revisited: 12 -> 16, with the
reason recorded at the constant. The centring maths below it is written in
terms of the constant, so it followed.

### Pins

The old ad-hoc geometry checks were replaced by a band-stack pin that reads
the geometry the window ACTUALLY built:

- every layout band has a measurable vertical range
- no two layout bands share vertical space
- the layout bands are stacked in order, top to bottom
- the last table row does not collide with the progress rail
- the column headers line up with the columns below them
- the plain column headers share the sortable headers' line
- the leaderboard frame is taller and wider than 720x520
- the gear panel keeps its own 400x470 size

The harness's mock needed two more facts to measure this: a FontString with
no explicit height is one text line tall (or every text band measures zero and
the pin measures nothing), and the header widgets had to be exposed
(`f.headerWidgets`).

### Revert reds (8 more)

ITEM4-f the frame back to 720x520 with 12 rows -> the frame-size pin, the
band-clash pin, the order pin, the last-row pin. ITEM4-g the sort readout
back on the header row -> the band-clash and order pins. ITEM4-h the stat
strip back in the header band -> the same two. ITEM4-i the footer back on the
progress rail -> the same two. ITEM4-j the rows spread wider than the table
band -> the clash, order and last-row pins. ITEM4-k the sortable and plain
headers misaligned -> the header-line pin. ITEM4-l a column header moved off
its column -> the column-alignment pin. ITEM4-m the gear panel stretched
with the window -> the gear-panel-size pin.

All 28 revert proofs across items 1-5 were re-run against the final tree; the
restored copy is 42/42.

## 2026-10-20 — [signal:done] Item 4 refined shipped

- **Worked on:** closed the fourth workstream. The leaderboard is now 900
  wide and considerably taller, it shows sixteen players at once, and its
  content is a stack of bands with the frame's height derived from that
  stack. The signal is written to `.signals/2026-10-20T16-05-00Z.json`.
- **Current state:** four commands green — Extras harness 42/42 on lua5.1,
  lua5.4 and luajit; `luacheck .` 0 warnings / 0 errors in 26 files;
  `verify_release_extras.sh` PASS; main harness 70/70. No commit, no staging.
- **Next step:** the operator re-tests in a Classic Era session — the
  leaderboard window must be bigger in both directions, show sixteen players
  without scrolling, and every band of it must be clear of its neighbours.

## 2026-10-20 — The mock's created frames were hidden; the client leaves them visible

- **Worked on:** a mock-fidelity item surfaced by the other lane: the Extras
  harness created every frame HIDDEN, and the client does not.
- **Current state:** DONE. All four commands green (Extras harness 42/42;
  luacheck 0/0 in 26 files; `verify_release_extras.sh` PASS; main harness
  70/70). `load_test.lua` is now 571 checks and `rankbrowser_test.lua` 307.
  No commit, no staging.
- **Next step:** the operator re-tests in a Classic Era session — the FIRST
  click on the leaderboard must OPEN it, and the second must close it.

### What the client actually does (VERIFIED in the mirror)

- **A frame the client creates is VISIBLE, and no template hides it.**
  Blizzard's own panels carry `hidden="true"` on the FRAME, never on the
  template:
  - `origin/classic_era` `Interface/AddOns/Blizzard_AddOnList/AddonList.xml:120`
    — `<Frame name="AddonList" enableMouse="true" inherits="ButtonFrameTemplate"
    mixin="AddonListMixin" hidden="true">`
  - `origin/classic_era`
    `Interface/AddOns/Blizzard_UIPanels_Game/Blizzard_GameMenu.xml` —
    `GameMenuFrame`, likewise `hidden="true"` on the frame.
  - The `ButtonFrameTemplate` chain itself carries no `hidden` attribute at
    all: `SharedUIPanelTemplates.xml:387` (`PortraitFrameBaseTemplate`),
    `:440` (`PortraitFrameTemplateNoCloseButton`), `:545`
    (`PortraitFrameTemplate`), `:708` (`ButtonFrameTemplate`).
- **And Blizzard's own code creates frames and then hides them explicitly** —
  `origin/classic_era`
  `Interface/AddOns/Blizzard_Calendar/Classic/Blizzard_Calendar.lua`:
  `eventButton = CreateFrame("Button", eventButtonPrefix..i, button,
  "CalendarDayEventButtonTemplate");` ... `eventButton:Hide();`

So a browser window created with `ButtonFrameTemplate` is on screen from the
moment it is created.

### The bug that was hiding in the mock

`RankBrowser.Toggle()` branches on `f:IsShown()`, and `RankBrowser.CreateUI`
never hid the frame. With the mock creating frames hidden, the harness took
the SHOW branch on the first toggle; in the game, with the frame visible from
creation, the first toggle would have taken the HIDE branch — **the first
click on the leaderboard would have closed a window that was already open.**
The mock's disagreement with the client is exactly what hid it.

### The fix

- **Production** (`RankBrowser.lua`): the browser window is hidden explicitly
  right after it is created (`:2189`), with the mirror citations in the
  comment; the gear panel is hidden the same way (`:1522`), so it is never on
  screen between being created and being filled in.
- **Mock**: `rankbrowser_test.lua` and `load_test.lua` now create frames
  VISIBLE, as the client does, with the citations in the mock's `newRegion`.
- **Pins**: a frame created in this environment is visible, as in the client
  (both harnesses); a newly created browser window is hidden before the first
  toggle; the FIRST toggle shows the browser; the second toggle hides it.

### Revert reds (3 more)

ITEM6-a the production stops hiding the window it creates -> the three
toggle pins plus the escape check. ITEM6-b the browser mock goes back to
creating frames hidden -> the mock-fidelity pin. ITEM6-c the load harness
mock goes back to creating frames hidden -> the same pin there.

All 31 revert proofs across items 1-6 were re-run against the final tree; the
restored copy is 42/42.

## 2026-10-20 — [signal:done] The mock's created frames shipped

- **Worked on:** closed the fifth workstream. The harness now models the
  client's visible-by-default frames, and the leaderboard hides the window it
  creates so the first click opens it. The signal is written to
  `.signals/2026-10-20T17-10-00Z.json`.
- **Current state:** four commands green — Extras harness 42/42 on lua5.1,
  lua5.4 and luajit; `luacheck .` 0 warnings / 0 errors in 26 files;
  `verify_release_extras.sh` PASS; main harness 70/70. No commit, no staging.
- **Next step:** the operator re-tests in a Classic Era session — the FIRST
  click on the leaderboard must OPEN it and the second must CLOSE it.





