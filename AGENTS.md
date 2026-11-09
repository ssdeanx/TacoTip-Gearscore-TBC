# AGENTS.md

start here. the detail lives in the linked files — read them before your first
edit. this file is an index, not a second copy.

## what this repo is

two addons, one repo: **TacoTip** (root, v1.0.0) and **TacoTip Extras**
(`TacoTip_Extras/`, v1.2.5), for five client families (era 11509, tbc
20506, titanforge 38002, forever 16001, retail 120105). the root doubles as
the workshop — `desks/`, `bench/`, `Tools/`, `OLD/` are not shipped.

## client families — classic vs forever (camelot)

the five clients are two API worlds. never cross them.

- **classic era 11509, tbc 20506, titanforge 38002** use the classic talent
  API (`GetNumTalentTabs`, `GetTalentInfo`, `GetTalentTabInfo`,
  `GetActiveTalentGroup`), installed by `Blizzard_DeprecatedSpecialization`
  (`## AllowLoadGameType: classic, standard`). `LibForeverInspector`'s
  `spec_table` / `talents_table` are this data. **the old tables are classic
  clients and are not valid for forever.**
- **forever 16001 is camelot.** `WOW_PROJECT_ID` is MAINLINE (1), like
  retail; the split is the interface version, and the UI lives in the
  `Camelot` folders (`Blizzard_PlayerSpells/Camelot/ClassTalents/…`,
  `Blizzard_InspectUI/Camelot/…`). In a Blizzard TOC, `[Game]` resolves to
  Camelot and `[Family]` resolves to the Mainline family.
- **a forever specialization is class-level; a class has three talent
  trees.** `C_SpecializationInfo.GetSpecializationInfo` answers the class
  spec ("Shaman"), which is why a retail-style talents line printed
  `Talents: Shaman`. The trees are trait node groups: names/icons come from
  `C_Traits.GetGroupDisplayInfoByTreeID(treeID)` (the struct carries
  `displayName` and `icon`); per-tree points come from
  `C_Traits.GetGroupCurrencyInfo(configID, groupIDs)` → `spentInTree`, and
  the inspected player's trait config is the documented constant
  `Constants.TraitConsts.INSPECT_TRAIT_CONFIG_ID = -1`
  (`TraitConstantsDocumentation.lua:352`), which Blizzard's Camelot
  `ClassTalentsFrame` loads for the inspect frame
  (`Interface/AddOns/Blizzard_PlayerSpells/ClassTalents/Blizzard_ClassTalentsFrame.lua:887`,
  `RefreshConfigID` -> `SetConfigID(..., INSPECT_TRAIT_CONFIG_ID)`). The
  `validInspect` gate is `C_Traits.HasValidInspectData()`
  (`SharedTraitsDocumentation.lua`): `true` means the client has the
  inspected player's trait config loaded. That config is
  the inspected player's ACTIVE group; the inactive group is attempted
  through `C_SpecializationInfo.GetTalentInfo` with `isInspect = true`,
  `target = <unit>`, `groupIndex = <g>` and is drawn only when the client
  answers.
  There are **primary and secondary spec groups** (dual spec at 40); the
  number of groups is `GetNumSpecGroups()` and Blizzard gates the second tab
  on `> 1` (`Blizzard_PlayerSpells/Camelot/ClassTalents/Blizzard_ClassTalentsFrame.lua:124`).
  The classic talent globals are not loaded on camelot.
- **if forever needs a spec icon or tree-name table, it must be a
  camelot-only table** (or read from `C_Traits`), gated on `isForever`.
  never build it from `lib.spec_table` / `lib.talents_table`.
- **every forever change is gated on `isForever` / `CI:IsForever()`**; no
  classic or retail path may shift. the old retail/classic talent block
  keeps its `show_talents and not isForever` gate byte-identical; the camelot
  readout is a separate `show_talents and isForever` branch.
- **the forever zone row is a client-map read, not a zone scan.**
  `C_Map.GetBestMapForUnit(unit)` is documented as *"Only works for the player
  and party members"* (`MapDocumentation.lua:49-60`), so the row is drawn only
  where the client answers; `C_Map.GetMapInfo(mapID).name` is the localized
  zone (`MapDocumentation.lua:312-325`, `UiMapDetails` at `:696-706`) and the
  label is the client's own `ZONE` string (`FriendsFrame.lua:1135`). scope is
  the owner frame's `unit`: player/target/party/raid only — nameplates, focus,
  pets and target-of-target are excluded even for players. a unit the client
  cannot place gets no row; never guess one.
- **the forever loot-window tooltip is native and must stay native.** it is
  `GameTooltip:SetLootItem` through a secure tooltip-data delegate
  (`TooltipDataHandler.lua:495-517,537`), the loot element rebuilds it every
  frame from its item button's `OnUpdate` (`LootFrame.lua:464-469`), and its
  data carries secret lines. blizzard documents that taint into `ProcessInfo`
  plus secret line data/text can make the tooltip display no lines
  (`GameTooltip.lua:994-1003`), so TacoTip must not add item rows, re-font,
  cap or restyle that tooltip. normal item tooltips are unaffected.

## read these first

| file | holds |
| :--- | :--- |
| `CAIRN.md` | evidence labels and the precedence ladder — how a claim is judged |
| `workshop.md` | the invariants, the client facts that bite, how to run a lane, the wago.tools recipe, package verification |
| `hands-up.md` | signal types, when to escalate, the problems seen in practice |
| `bench/audits/2026-10-20-inspect-and-guild-line-history.md` | the 0.7.9–0.8.3 inspect-frame and guild-line traps, and what is load-bearing now |
| `bench/audits/2026-10-20-session-retrospective.md` | last release: what went wrong and what now prevents it |

## the short version

- **one lane, one complete task**, and use the four skills every time
  (`@desk-open`, `@desk-journal`, `@bench-read`, `@signal-write`); the desk's
  `done` signal is the hand-off — `workshop.md` → "how to run a lane".
- **client truth**: `/home/sam/wow-ui-source`, read-only and
  `origin/`-qualified; client strings the mirror cannot carry: wago.tools;
  the operator's in-game observation outranks both — `workshop.md` and
  `CAIRN.md`.
- **the invariants** — the era range gate, the gearscore formula, the retail
  bracket, the wire format, the saved-variable shapes, the one-argument
  `CanInspect`, no invented translations — are listed once, in `workshop.md`
  → "the invariants". read them before editing.

## commands

    bash Tests/harness/run_all.sh                   # main, 72 invocations (repeat with LUA=lua5.4 / luajit)
    bash TacoTip_Extras/Tests/harness/run_all.sh    # extras, 42 × 3 interpreters
    luacheck .                                     # 0 warnings / 0 errors
    bash Tools/verify_release.sh --worktree         # tacoTip package, must PASS
    bash Tools/verify_release_extras.sh --worktree  # extras package, must PASS

`--worktree` validates the tree you ship; the default validates a commit you
are probably not shipping.

## do not

- never change anything the player can see — bars, frames, anchors, colors,
  sizes, text — unless the request names it.
- a second symptom gets one line in the report, never an edit.
- under time pressure, report state instead of finishing the job: what changed,
  what didn't, and what was not run.
- no state-changing git — nothing is staged or committed by design; the two
  verifiers are the only permitted git use.
- no browsing from a lane. no hash-based verification — read the code and run
  the suites.
- no new files unless asked. no locale key without a sourced translation.
- do not edit `gearscore.lua` except to guard an existing call.
- never remove, weaken, or rework the FojjiCore `GameTooltip` row block. it is
  specific to FojjiCore, load-bearing, and an operator invariant — see
  `workshop.md` and `hands-up.md`.
- never report "done" with a red tree.
