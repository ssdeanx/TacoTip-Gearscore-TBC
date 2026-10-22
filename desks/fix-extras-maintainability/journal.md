# fix-extras-maintainability — Journal

## 2026-10-20 — Desk opened

- **Purpose:** The TacoTip **Extras** side of the final maintainability audit
  (5 HIGH + 9 MEDIUM + 7 LOW across both add-ons). The main add-on's side is
  owned by another lane; **no main file was touched**.
- **Scope:** `TacoTip_Extras/Locale/*.lua` (all 11), `TacoTip_Extras/Core.lua`,
  `TacoTip_Extras/RankBrowser.lua`, `TacoTip_Extras/Tooltips.lua`,
  `TacoTip_Extras/Frames.lua`, `TacoTip_Extras/README.md`,
  `TacoTip_Extras/CHANGELOG.md`, `TacoTip_Extras/Tests/harness/load_test.lua`,
  `TacoTip_Extras/Tests/harness/rankbrowser_test.lua`.
  No commit, no staging.
- **Baseline measured (not assumed):** Extras harness `TOTAL 42 invocations:
  42 passed, 0 failed` (lua5.1 / lua5.4 / luajit); `cd TacoTip_Extras &&
  luacheck .` → `Total: 0 warnings / 0 errors in 26 files`;
  `bash Tools/verify_release_extras.sh` → `verify_release_extras: PASS`; the
  main add-on's harness → `TOTAL 71 invocations: 71 passed, 0 failed`.
- **Operator decision carried into item 2:** delete the dead locale keys; do
  NOT wire the hardcoded English status text through the locale keys (that
  would be ~47 new sentences x 11 locales — a separate translation release).

## 2026-10-20 — Items 1-8 landed, pinned, revert-proven

- **Item 1 (HIGH) — the ▲ glyph.** `LB_TOP` shipped `\226\152\160` (U+2620
  BALLOT BOX) in ten of the eleven locales, so the footer button read "☐ Top"
  in every language except English. VERIFIED by grep that the bad byte
  sequence occurred exactly once per file and only on the `LB_TOP` line;
  replaced with `\226\150\178` (U+25B2) in deDE/esES/esMX/frFR/itIT/koKR/
  ptBR/ruRU/zhCN/zhTW. `LB_MY_RANK_ARROW` (▼, `\226\150\188`) was already
  correct and was not touched. **VERIFIED** by the client mirror for the
  glyph rule only in the sense that the bytes are the client's own arrow
  shape; the locale files are the add-on's own strings.
- **Item 2 (HIGH) — the dead locale keys.** The read set was resolved from
  the SOURCES, not from a hand-written list: literal `L["KEY"]` lookups plus
  the five dynamic families (`HELP_<NAME>_HEADING` / `HELP_<NAME>_<n>` from
  the Options page's HELP table, `CLASS_<TOKEN>` from the leaderboard's
  CLASS_ORDER and its `return "UNKNOWN"`, `LB_COL_*` from the COLUMNS table's
  `label` field, `SORT_*` from the SORTS table, `MODE_*` from the choice
  tables). **38 keys are defined in all eleven files and read by no code
  path**: BLANK, BLANK_DESC, GEAR_CLOSE, GEAR_NO_ITEMS,
  INTEGRATION_COMPATIBLE/INCOMPATIBLE/MISSING, LB_MY_RANK, LB_SCAN_IDLE,
  LB_TIP_CLASSRANK, OPTIONS_PAGE, OPTIONS_TAB_EQUIPMENT, OPTIONS_TAB_TOOLTIP,
  the whole OPT_* family (14), the whole REMOTE_* family (5) and the whole
  SECTION_* family (4). Deleted from all eleven files. `CLASS_UNKNOWN` was in
  the audit's candidate list but is **read** (`L["CLASS_" .. classToken]` at
  RankBrowser.lua, and `classTokenOf` returns `"UNKNOWN"`), so it was KEPT.
  `GEAR_CLOSE`, `LB_SCAN_IDLE` and the REMOTE_* family were still unread —
  the audit's "some may have become live" caution was checked, not assumed.
- **Item 2 also found a PRE-EXISTING defect the audit did not name.** The new
  "identical key set" pin failed on the untouched tree: enUS defined
  `LB_GUILD`, `LB_TIP_PVP_RANK`, `LB_TIP_ARENA`, `LB_TIP_RANK_SYNCED` and
  `GEAR_DATA_UNAVAILABLE`, and the other ten locales did NOT — so those five
  strings read English in ten languages. They were translated into all ten
  (guild label, PvP rank, arena best, rank synced, gear-data-unavailable
  note) and the pin now passes.
- **Item 3 (HIGH) — the escape registration.** The audit's line numbers were
  stale (the area had moved), so the current code was re-read first.
  `RankBrowser.RegisterEscapeClose` registers ONE owner and refuses a second
  caller; the browser registers first, so the gear panel's call was a no-op
  while the comment claimed "the same three-route registration the browser
  uses". Chose the audit's second option: **delete the no-op call and make
  the comment describe the real mechanism**. Registering the panel for real
  was rejected on evidence: it would add the panel to UISpecialFrames, where
  the engine hides the topmost special frame and would take the browser down
  with the panel. The panel is closed by the browser's `closeIfShown`, which
  checks the panel first. Behaviour a player sees is unchanged.
- **Item 4 (MEDIUM) — the class-colour chain.** `Core.GetClassColor(classToken,
  options)` now owns the whole chain (Shaman-blue override, then
  CUSTOM_CLASS_COLORS, then RAID_CLASS_COLORS). Each surface keeps its OWN
  accept rule and its OWN fallback: the tooltip and the frame accept only
  three finite numbers in 0..1 and fall back to neutral grey; the leaderboard
  accepts any three numbers and falls back to its own hardcoded 13-entry
  table. **No colour changes on screen.** The existing behavioural pins (the
  tooltip's Shaman blue / client pink, the leaderboard's
  "prefers RAID_CLASS_COLORS, falls back to hard table") stayed green
  throughout.
- **Item 5 (MEDIUM) — the gear panel geometry.** Every duplicated literal is
  now a named constant and both the rows and the dots are computed from one
  `gearRowTop(index)`. **Every pixel is unchanged**, and the harness now pins
  the panel's size, every row's x/y and width, every dot's x/y and size, and
  the note's position and width.
- **Item 6 (MEDIUM) — two identical functions.** `setFreshEquipmentDisplayDefaults`
  and `setMigratedEquipmentDisplayDefaults` were byte-identical; collapsed to
  `setEquipmentDisplayDefaults`. Both call sites are kept and the fresh
  profile still starts Detailed / Unenhanced off / locked (all three values
  are now pinned).
- **Item 7 (MEDIUM) — the template title.** See the mirror citation below.
  The harness's `CreateFrame` mock now publishes the client's
  `<FrameName>TitleText` global for a template that confers one, and the
  title band is pinned at 0.
- **Item 8 (LOW) — documentation.** The `show_server_rank` / `showServerRank`
  alias and the cross-add-on mapping are explained in `Core.lua`; the README's
  `updated:` is 2026-10-20; the "Twelve scenarios per interpreter" line is
  corrected to fourteen (12 load scenarios + 2 leaderboard-behaviour runs =
  42 total); and a `### Extras maintenance pass` subsection was added to the
  existing `[1.2.3]` section of the CHANGELOG. No version bump; earlier
  sections untouched.

### Item 7 — the mirror citation (VERIFIED, read-only)

`/home/sam/wow-ui-source`, branch-qualified, `git show origin/<branch>:<path>`:

- **origin/classic_era** `Interface/AddOns/Blizzard_SharedXML/Classic/SharedUIPanelTemplates.xml`
  - `:708` `<Frame name="ButtonFrameTemplate" inherits="PortraitFrameTemplate" virtual="true">`
  - `:545` `<Frame name="PortraitFrameTemplate" inherits="PortraitFrameTemplateNoCloseButton" virtual="true">`
  - `:440` `<Frame name="PortraitFrameTemplateNoCloseButton" inherits="PortraitFrameBaseTemplate" virtual="true" mixin="PortraitFrameTemplateMixin">`
  - `:496` `<FontString name="$parentTitleText" inherits="GameFontNormal" text="" parentKey="TitleText" wordwrap="false">` — a DIRECT child of the template root.
- **origin/classic_anniversary** — the same file, the same line numbers
  (`:387 / :427 / :440 / :496 / :545 / :708`).
- **origin/classic_titan** `Interface/AddOns/Blizzard_SharedXML/Classic/SharedUIPanelTemplates.xml`
  — `:387` PortraitFrameBaseTemplate, `:419` `<Frame parentKey="TitleContainer" frameLevel="510">`,
  `:427` `<FontString name="$parentTitleText" ... parentKey="TitleText">`,
  `:530` PortraitFrameTemplateNoCloseButton, `:532` PortraitFrameTemplate,
  `:580` ButtonFrameTemplate.
- **origin/live** `Interface/AddOns/Blizzard_SharedXML/Mainline/SharedUIPanelTemplates.xml`
  - `:684` `<Frame name="ButtonFrameTemplate" inherits="ButtonFrameBaseTemplate" virtual="true">`
  - `:660` `<Frame name="ButtonFrameBaseTemplate" inherits="PortraitFrameBaseTemplate" virtual="true">`
  - `:544` `<Frame name="PortraitFrameBaseTemplate" mixin="PortraitFrameMixin" virtual="true">`
  - `:576` `<Frame parentKey="TitleContainer" frameLevel="510">`
  - `:584` `<FontString name="$parentTitleText" inherits="GameFontNormal" text="" parentKey="TitleText" wordwrap="false">`
- **origin/forever** `Interface/AddOns/Blizzard_SharedXML/Mainline/SharedUIPanelTemplates.xml`
  — `:711` ButtonFrameTemplate, `:687` ButtonFrameBaseTemplate, `:566`
  PortraitFrameBaseTemplate, `:600` TitleContainer, `:608` `$parentTitleText`.

That the FontString resolves to the global **`<FrameName>TitleText`** is the
client's own behaviour, seen on the same templates:

- **origin/classic_era** `Interface/AddOns/Blizzard_CharacterFrame/Cata/CharacterFrame.xml:282`
  `<Frame name="CharacterFrame" toplevel="true" movable="true" parent="UIParent" hidden="true" mixin="CharacterFrameMixin" inherits="ButtonFrameTemplate">`
  and `Interface/AddOns/Blizzard_CharacterFrame/Cata/CharacterFrame.lua:115`
  `CharacterFrameTitleText:SetText(displayInfo.title);`
- **origin/live** `Interface/AddOns/Blizzard_ItemUpgradeUI/Mists/Blizzard_ItemUpgradeUI.xml:108`
  `<Frame name="ItemUpgradeFrame" inherits="EtherealFrameTemplate" toplevel="true" movable="true" parent="UIParent" enableMouse="true" hidden="true" mixin="ItemUpgradeMixin">`
  and `Interface/AddOns/Blizzard_ItemUpgradeUI/Mists/Blizzard_ItemUpgradeUI.lua:29`
  `ItemUpgradeFrameTitleText:SetText(ITEM_UPGRADE);`

The client's own mixin reaches the same FontString through the parent key:
`origin/classic_era Interface/AddOns/Blizzard_SharedXML/PortraitFrame.lua:5`
`return self.TitleContainer.TitleText;` (and the same line on origin/live's
`Interface/AddOns/Blizzard_SharedXML/PortraitFrame.lua`).

So the client DOES publish it, and the harness models it. **No assumption
recorded** — this is the client source, not a guess.

### Pins added, and their revert reds (each mutated on a COPY)

Copy at `/tmp/opencode/mut/` (the add-on plus the main tree's
`Tests/harness/mock_contract.lua` and `Libs/`, which the harness reads).
The working tree was never mutated.

| Mutation | Red |
| :--- | :--- |
| `LB_TOP` back to `\226\152\160` in deDE | `FAIL every locale's LB_TOP starts with the same up-triangle bytes as enUS` |
| `OPT_TOOLTIP_MODE` re-added to all 11 locales | `FAIL every locale key is read somewhere in the add-on` |
| `LB_GUILD` dropped from frFR only | `FAIL every locale defines the same key set as enUS` |
| the escape handler stops closing the gear panel first | `FAIL Escape leaves the leaderboard up while the panel was open` |
| `Core.GetClassColor` ignores the caller's accept rule | `FAIL the permissive rule keeps a community colour outside 0..1` |
| `GEAR_ROW_STEP` 22 → 24 | `FAIL every gear panel row sits where it always sat` + `FAIL every gear panel dot sits where it always sat` |
| the mock stops publishing the template title | `FAIL the client publishes the browser frame's template title` + `FAIL the title band collapses to 0 when the template provides the title` + `FAIL the template title carries the window title` |
| the fresh-profile default stops locking the positions | `FAIL default equipment display starts with the positions locked` |

### Final validation (all four commands, quoted)

- `bash TacoTip_Extras/Tests/harness/run_all.sh` → `TOTAL 42 invocations: 42 passed, 0 failed`
- `cd TacoTip_Extras && luacheck .` → `Total: 0 warnings / 0 errors in 26 files`
- `bash Tools/verify_release_extras.sh` → `verify_release_extras: PASS`
- `bash Tests/harness/run_all.sh` (the MAIN add-on) → `TOTAL 71 invocations: 71 passed, 0 failed` — unchanged, and no main file was touched.

### Deviations and things the operator should know

- **The audit's line numbers were stale for item 3** (`RankBrowser.lua:1599-1600`
  and `:2685-2687`): the area had moved. The code was re-read before the
  edit, as instructed.
- **Item 2 grew by five translations.** The operator's decision was to delete
  the dead keys rather than localize the status text. That decision stands
  and was followed. But the new "identical key set" pin exposed five keys
  enUS defined and the ten translations did not, so those five strings read
  English in ten languages. Leaving that would have shipped a knowingly
  half-localized UI, so they were translated (five short strings x ten
  languages). This is NOT the ~47-sentence translation work the operator
  deferred — it is five labels that were already supposed to be translated.
- **The locale files' blank-line runs were normalised** (two or more
  consecutive blank lines collapse to one) where removing a dead key left a
  gap. Formatting only; no value changed.
- **The rankbrowser harness now loads `Core.lua`** (it did not before). The
  class-colour chain lives in Core, and the harness was grading a
  leaderboard whose rows were coloured by a fallback path the real client
  never takes. The TOC loads Core first, so this is also more faithful.
- **`RankBrowser.GetTitleBandHeight()` was added** — a read-only accessor,
  on the same precedent as the existing `RankBrowser.GetSlotRows()`, so the
  harness can pin the title band at 0 directly rather than inferring it from
  a frame height.
- **Not touched, deliberately:** the main add-on's files; the hardcoded
  English status text itself (the operator deferred it); the `OPT_SHAMAN_BLUE`
  key (deleted as dead — the Core comment names it as the retired spelling
  and points at the live `HELP_SHAMANBLUE_HEADING`).
