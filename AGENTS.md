# AGENTS.md

start here. the detail lives in the linked files — read them before your first
edit. this file is an index, not a second copy.

## what this repo is

two addons, one repo: **TacoTip** (root, v1.0.0) and **TacoTip Extras**
(`TacoTip_Extras/`, v1.2.6), for five client families (era 11509, tbc
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
- **forever 16001 is camelot, and its project id is 18 — not MAINLINE.**
  `Interface/AddOns/Blizzard_ProjectConstants/Camelot/ProjectConstants.lua:1-2`
  is the whole file and reads `WOW_PROJECT_CAMELOT = 18; WOW_PROJECT_ID =
  WOW_PROJECT_CAMELOT;`. older notes here said `WOW_PROJECT_ID` was MAINLINE
  (1); they were wrong, and reading identity from MAINLINE alone makes
  `isMainline` false on Forever, which then only reaches the right family via
  the 16000-19999 interface-band fallback. when that slot is unreadable the
  whole add-on classifies Forever as `unknown` and every `isForever` branch
  switches off silently. `LibForeverInspector` reads `WOW_PROJECT_CAMELOT`
  FIRST and keeps the band only as a fallback. the split is still the interface
  version, and the UI lives in the
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

## forever secrets — the rules that actually bite

read this before touching any `Unit*` call. each rule is from the client
source at the pin and, for the mechanism, [warcraft wiki "it's secret"](https://warcraft.wiki.gg/wiki/Secret_Values).

- **`SecretArguments` governs the ARGUMENT, not the return.** a function
  marked `SecretArguments = "AllowedWhenUntainted"` refuses a secret value
  from add-on code with an immediate Lua error, e.g.
  `bad argument #1 to 'UnitExists' (... Secret values are only allowed during
  untainted execution for this argument.)`. add-on execution is *always*
  tainted, so **never pass a possibly-secret token to such a function**.
  `UnitExists`, `UnitIsPlayer`, `UnitIsConnected`, `UnitIsDeadOrGhost`,
  `UnitInParty`, `UnitGroupRolesAssigned`, `UnitIsSameServer` and
  `UnitDistanceSquared` are all in this class — their *returns* are plain, and
  that is exactly what makes the argument hazard easy to miss.
- **`type(v)` is not a secrecy test.** `type(secret)` returns the real type,
  so a secret string reports `"string"` and a secret number reports
  `"number"`. `type(v) == "string"` therefore does NOT prove a token is safe.
  `type()` is safe to *call* on a secret, which is why nil tests use
  `type(v) == "nil"` rather than `v == nil` — an `==` on the guard's first line
  can raise before the `pcall` beneath it runs.
- **`pcall` does not make the ANSWER safe.** the classic mistake is
  `local ok, v = pcall(UnitCanAttack, ...)` then `if (ok and v == false)`: the
  pcall guarded the call, and the **comparison** is what raises. this exact
  shape was in `main.lua` and is now guarded. same trap for `UnitIsUnit`,
  `UnitInRaid`, `UnitIsPVP`, and for `x ~= ""` on a secret string. test the
  value (`issecretvalue`) before you compare it, or route through a `safe*`
  helper.
- **`UnitIsEnemy` is not a faction test on this client** (and TacoTip uses it
  nowhere). Forever reports `UnitIsEnemy`/`UnitCanAttack` as "attackable right
  now", false for an unflagged enemy, in a sanctuary or on another shard. a
  faction comparison is `UnitFactionGroup(unit) ~= UnitFactionGroup("player")`,
  and `UnitFactionGroup`'s argument is a cstring under `AllowedWhenUntainted`,
  so the token is tested first.
- **health is never read for display.** `UnitHealth`/`UnitHealthMax` can be
  secret numbers; the safe sink is `StatusBar:SetMinMaxValues`/`SetValue`, which
  is `AllowedWhenTainted` + `BarValue`. TacoTip does not read health at all —
  the bar is Blizzard's own `GameTooltipStatusBar` and the client drives it.
- **no `COMBAT_LOG_EVENT_UNFILTERED`.** it throws on Forever; use unit events
  (`UNIT_HEALTH`, `UNIT_POWER_UPDATE`, `UNIT_SPELLCAST_*`, `PLAYER_REGEN_*`,
  `ENCOUNTER_START`/`_END`, `ZONE_CHANGED_NEW_AREA`). neither addon registers it.
- **only secret BOOLEANS fail a boolean test.** truthiness on a secret string
  or number is allowed and always true; comparisons and arithmetic always
  raise. so `if (secretUnitName)` is legal — `if UnitIsUnit(a,b) then` is not
  (`SecretWhenUnitComparisonRestricted`), and `if (level > 0)` is not.
- **`issecretvalue` / `canaccessvalue` throw too.** both are
  `AllowedWhenUntainted`, so from tainted code a *refused* call returns
  `ok = false` from `pcall` — and a throw means **is secret**. the guard is
  `if (not okSecret or isSec == true) then return true end`; the weak form
  `okSecret and isSec` inverts the one case it exists for.
- **`pcall` does not clear a blocked protected call.** a refused protected
  call can fail with no Lua error at all — the only symptom is the instance
  action counter, which `/reload` does not reset. do not treat `pcall` success
  as proof the call was permitted.
- **a tooltip-data table is indexed only if `canaccesstable` says so.**
  `issecretvalue(data)` is the WRONG test for the payload handed to an
  Item/Unit post-call: once untainted code stores a secret value as a table
  key, the table is flagged secret *and* inaccessible, and the **index itself**
  raises ("attempted to index a forbidden table") before any test on the result
  could run. `canaccesstable(table)` is the documented predicate ("permissions
  to index secret tables"), is itself `AllowedWhenUntainted`, so `pcall` it and
  read a throw as "not readable". `TT.tooltipDataReadable` is the gate; every
  `data.<field>` read goes through it. this applies to item tooltips and unit
  tooltips alike.
- **`WorldFrame` is anchoring, not secrecy.** `TT:GetMouseFocus()` returns
  `WorldFrame` as the sentinel for "the cursor is over the 3D world, not a UI
  frame" (`main.lua:4803-4812`), and unit hovers in the world anchor off it
  (`main.lua:4285`, `:4318`, `:4350`). it carries no secret payload; do not
  confuse it with the tooltip-data rules above.
- **`GameTooltip:SetUnit` / `SetLootItem` / `SetLootRollItem` are
  secret-delegated on purpose** (`TooltipDataHandler.lua:582`, `:537-538`;
  `AddTooltipDataAccessorDelegate` `:488-517`). hand a secret token to the
  accessor and let the secure delegate strip taint; never try to re-derive or
  read that token yourself first.
- **test the restrictions without a group or an instance.** engine cvars
  force them on anywhere (wiki-documented; not in the Lua mirror, so
  unverifiable from source): `addonEncounterRestrictionsForced`,
  `addonCombatRestrictionsForced`, `addonMapRestrictionsForced`,
  `addonChallengeModeRestrictionsForced`, `addonPvPMatchRestrictionsForced`,
  `addonChatRestrictionsForced`. they do not persist across a restart.
- **the companion addon follows the SAME rules.** `TacoTip_Extras` has its own
  strong `isSecretValue` (`Core.lua`) and local copy (`RankBrowser.lua`), never
  overrides a `GameTooltip` method, uses no secure attributes, and makes no
  bare `Unit*` call — but it had `x ~= ""` comparisons *before* the secret test
  in `Scanner`/`Cache`/`Frames`/`RankBrowser`/`RankDB`/`RankSync`, and
  `Scanner.capturePlayerCells` stored a possibly-secret `UnitClass` token and
  `UnitLevel` into the rank record (where it was compared, then did `% 1`
  arithmetic, then became a secret cache key). all fixed 2026-11-10. Extras also
  **delegates client identity** to `inspector:IsForever()`/`IsClassic()` etc. and
  must never re-derive it from `WOW_PROJECT_ID` — a MAINLINE test is false on
  Forever.
- **the boundary helpers are the pattern**: `safeUnitExists`,
  `safeUnitIsPlayer`, `safeUnitIsConnected`, `safeUnitIsDeadOrGhost`,
  `safeUnitGUID`, `safeUnitIsUnit` in `LibForeverInspector`, and the `TT.safe*`
  twins in `main.lua`. a new `Unit*` call goes through one of them or states in
  a comment why it cannot be secret. `detect_test` pins the nameplate
  isolation separately from the token test — a refused token is *not* a
  distance skip.

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

    bash Tests/harness/run_all.sh                   # main, 74 invocations (repeat with LUA=luajit)
    bash TacoTip_Extras/Tests/harness/run_all.sh    # extras, 42 invocations (LUA=luajit to repeat)
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
