# 2026-10-19 — Final documentation-truth pass (both add-ons)

**Agent:** `final-chronicler` · **Run:** `finalchronicler`
**Scope:** `README.md`, `CHANGELOG.md`, `TacoTip_Extras/README.md`,
`TacoTip_Extras/CHANGELOG.md`, `Tests/harness/README.md`.
**Code state:** frozen and verified by the caller (main harness 70/70, Extras
42/42, luacheck 0/0). This pass changed **no** code, no TOC, no version, no
test, and no other file.

Method: every claim was checked against the final tree with `grep`/`read` and a
file:line was taken for the code the claim names. Claims that could not be
settled from the tree are reported, not changed.

---

## (a) Drift found and corrected

### A. Main `CHANGELOG.md` — `[0.8.4]` line references

The whole `[0.8.4]` section was written on 2026-10-18 against the tree as it
stood then (`desks/main-publish-docs/journal.md:10-12` shows the same references
being taken). The code has since moved. Every reference below was re-pointed
at the code it names. Behavioural claims were checked too and are unchanged —
only the coordinates moved.

| # | Claim (before → after) | Code evidence |
| :--- | :--- | :--- |
| 1 | `options.lua:284` → `options.lua:294` | `TT:SafeSanitizeConfig` defined at `options.lua:294` |
| 2 | `options.lua:361-365` → `options.lua:371-374` | the five-literal `custom_anchor` allowlist check |
| 3 | `options.lua:236-278` → `options.lua:233-288` | media-allowlist table + `isKnownMediaValue` (builtin tables + LibSharedMedia) |
| 4 | `LibForeverInspector.lua:5353-5377` → `:5470-5489` | `GetSpecialization` returns `nil` for an uncached/spec-less unit (`return nil` at `:5488`) |
| 5 | `main.lua:2117-2118` → `main.lua:2299-2300` | `local spec1 = CI:GetSpecialization(guid, 1)` / `if (spec1) then` |
| 6 | `LibForeverInspector.lua:5540-5554` → `:5652-5670` | `GetActiveTalentGroup` claims group 1 only on a resolved group |
| 7 | `main.lua:2146` → `main.lua:2328` | `local active = CI:GetActiveTalentGroup(guid) or 1` |
| 8 | `LibForeverInspector.lua:4927-4939` → `:5029-5037` | `queueDropped` / `lastQueueDropGuid` / `lastQueueDropAge` |
| 9 | `LibForeverInspector.lua:107-117` → `:113-127` | `GetBuildInfo` type guard, `interfaceVersion = 0` default |
| 10 | `pawn.lua:8-19`, `169-172` → `pawn.lua:42-45`, `122-123`, `198-201` | `isPawnLoadedAtLoad` snapshot, `WasAvailableAtLoad`/`IsAvailable`, `GetScore` availability gate (`return 0, "", "|cffffffff"`) |
| 11 | `options.lua:2591-2595` → `options.lua:2740-2744` | the Pawn checkbox reads the live probe on Refresh |
| 12 | `main.lua:139`, `2235` → `main.lua:161-168`, `2417` | file-scope snapshot; render gate `isPawnLoaded and TT_PAWN ...` |
| 13 | `main.lua:3752-3754` → `main.lua:4141-4143` | diag problem `Pawn detected after load -- scores unavailable until reload` |
| 14 | `gearscore.lua:102-118,135` → `gearscore.lua:102-126`, `144` | `RequestLoadItemDataByID` + its `TT_GS` export |
| 15 | `pawn.lua:35-45` → `pawn.lua:61-70` | `pawnRequestLoadItemDataByID` routes through the shared home |
| 16 | `pawn.lua:143-166`, `99-114` → `pawn.lua:168-174`, `125-140` | `DrainItemCache` alias; `ResolvePlayerGUID` delegation |
| 17 | `main.lua:307-313` → `main.lua:386-397` | `pipelineErrorsSuppressed` + bounded 5-message ring |
| 18 | diag `3807-3809` → `4229-4231` | `pipeline errors suppressed` / `suppressed (up to 5)` |
| 19 | `main.lua:1092-1101` → `main.lua:1192-1205` | per-cause unit-resolution counters |
| 20 | diag `3523-3528` → `3915-3917` | `no-tooltip` / `no-source` / `unresolved` |
| 21 | `main.lua:1127,1137` → `main.lua:1231,1241` | guarded `tooltipIsMouseover` probes |
| 22 | diag `3519` → `3903` | `mouseover guard hits` |
| 23 | `main.lua:1307,1316` → `main.lua:1411,1420` | portrait `SetUnit` / `SetPortraitTexture` failures |
| 24 | diag `3518` → `3902` | `portrait set failures` |
| 25 | `main.lua:3312` → `main.lua:3675` | `InspectGuildFrame_Update` guard |
| 26 | diag `3530` → `3919` | `inspect guild guard caught` |
| 27 | `LibForeverInspector.lua:5258-5280`, `3861-3867` → `:5375-5394`, `3889-3890` | `ensureTickersInstalled` + the `ADDON_LOADED` retry |
| 28 | `main.lua:3769-3771` → `main.lua:4167-4169` | diag problem `inspect engine tickers not installed ...` |
| 29 | `options.lua:39-62`, `72-89` → `options.lua:49-72`, `86-99` | `applyScanSetting`; `recordOptionsRegFailure` |
| 30 | `main.lua:3759-3763` → `main.lua:4145-4152` | `TT.optionsRegErrors` surfaced in `problems[]` |
| 31 | `options.lua:664-718`, `720-769` → `options.lua:808-841`, `843-867`, `869-918` | per-step/per-page registration pcalls |
| 32 | `options.lua:2233-2242`, `2600-2604` → `options.lua:2377-2392`, `2749-2753` | the scan checkbox follows `lib.scanEnabled` |
| 33 | `gearscore.lua:141-144,617-619` → `gearscore.lua:147-153`, `620`; `pawn.lua:248-251` → `pawn.lua:281-283` | `TT_GS:CountPendingHidden` and its two call sites |
| 34 | `main.lua:3520` → `main.lua:3909` | diag `not-ready scores hidden (pending)` |
| 35 | `main.lua:2720-2750` → `main.lua:2900-2955` | item fire-and-forget + bounded 0.5 s repaint |
| 36 | diag `main.lua:3521` → `main.lua:3910` | diag `item refresh fire-and-forget` |
| 37 | `LibForeverInspector.lua:3722-3727,3782-3789,4964-4979,5014-5019` → `:3739-3744`, `3795-3810`, `5054-5090`, `5127-5137` | watchdog grace identity + queue-wait stats |
| 38 | `main.lua:3593-3597` → `main.lua:3980-3986` | `last watchdog drop`, `max/avg queue wait` |
| 39 | `LibForeverInspector.lua:4403` → `:4464`; diag `main.lua:3589` → `main.lua:3975-3979` | `lastErrorAt` + the `last error at (uptime)` line |
| 40 | `main.lua:2430-2451` → `main.lua:2612-2633`; diag `3522` → `3911` | power-bar `RegisterUnitEvent` fallback |
| 41 | `main.lua:3680-3716` → `main.lua:4064-4110` | four-key media diagnostics |
| 42 | `main.lua:254-260` → `main.lua:337-343`; `LibForeverInspector.lua:875-886` → `:885-895` | `getPlayerClass()` per call; lazy WotLK glyph reverse table |
| 43 | `gearscore.lua:185-191` → `gearscore.lua:187-194` | explicit unknown-family `1000` branch |
| 44 | `main.lua:3662-3664` → `main.lua:4051-4053` | diag problem `client family could not be resolved` |
| 45 | `main.lua:1386-1404` → `main.lua:1550-1564` | terminal `UpdateTooltip`/`SetUnit` capture with the re-entrancy guard unlatched |
| 46 | `gearscore.lua:162-194` → `gearscore.lua:155-199`; `gearscore.lua:187-193` → `:187-194` | the Batch-5 bracket block as it stands |
| 47 | `pawn.lua:15-29` → `pawn.lua:8-40`; `options.lua:24-39` → `options.lua:16-38` | the single `tonumber`-guarded version home + the options probe |
| 48 | `run_all.sh:69,100,124-125` → `run_all.sh:69,103-106,123-127,137-140` | the retail rows and the 1000-band comment |
| 49 | `detect_test.lua:159,173` → `detect_test.lua:159,174` | `CAMELOT_CONSTS`; the `bracket()` mirror |
| 50 | `main.lua:4154-4174` → `main.lua:4485-4504` | `MAX_STATIC_POPUP_DIALOGS` + `isSecureMenuBusy` |
| 51 | `main.lua:4256-4341` → `main.lua:4559-4671` | mover tick / Show+Hide hooks / `ShowExample` / drag `OnUpdate` / right-click confirm |
| 52 | `main.lua:4257`, `4266`, `4277`, `4338`, `4307`, `4232` → `4588`, `4597`, `4608`, `4669`, `4638`, `4563` | the six early-return / guard sites |
| 53 | `options.lua:669-705,801-802` → `options.lua:697-714`, `800-803`; `options.lua:669-692` → `options.lua:703-713` | the `LoadAddOn` ledger |
| 54 | `main.lua:3865-3874` → `main.lua:4154-4161` | `options load failures` in `problems[]` |
| 55 | `pawn.lua:132-156` → `pawn.lua:142-166`; `pawn.lua:142-144` → `pawn.lua:152-154` | `TT_PAWN:GetItemScore` nil-`scaleName` guard |
| 56 | `main.lua:3037-3070,3099-3115` → `main.lua:3308-3337` | `onGameTooltipSetDefaultAnchor` parent probe |
| 57 | `main.lua:4154` → `main.lua:4485` | `MAX_STATIC_POPUP_DIALOGS = 4` |
| 58 | `TacoTip_Extras/TacoTipAdapter.lua:2085-2147` → `:2085-2146` | `scoreColorFallbacks` block |
| 59 | `TacoTip_Extras/Tooltips.lua:758-770` → `:778-792` | `Tooltips.GetDebugState` |
| 60 | `TacoTip_Extras/RankBrowser.lua:36-64` → `:58-70` | the strata / level / alpha comment block |
| 61 | `options.lua:783`, `:785`, `724-725` → `options.lua:823-824`, `:882`, `:884` | the three `Settings.*` call sites |

**Count:** 61 line-reference corrections in the `[0.8.4]` section. Behavioural
claims in that section were all re-checked and hold (see §B).

### B. Main `CHANGELOG.md` — counts and one false claim

| Claim (before → after) | Evidence |
| :--- | :--- |
| `batch8_pane_test.lua` "(27 checks, all five clients)" → "(26 checks, all five clients)" | 27 `check(` occurrences in `Tests/harness/batch8_pane_test.lua`, one of which is the definition at `:453`; no `check()` sits inside a loop, so the file runs 26 checks |

### C. `TacoTip_Extras/CHANGELOG.md` — `[1.2.3]`

| Claim (before → after) | Evidence |
| :--- | :--- |
| "The six call sites, and what each one actually measures:" → "The six call sites this change converted, and what each one actually measures:" | The shipped tree has **ten** `GetServerTime` call sites (`RankDB.lua:254,466,652,833,890`; `RankBrowser.lua:233,381`; `Scanner.lua:327,799`; `RankSync.lua:1350`). The four extra ones belong to the later Stage-2/4/5 subsections of the same release. The six the change converted are the ones listed. |
| `RankDB.lua:444` → `RankDB.lua:454` | `function RankDB.BuildSortedIndices(realm)` at `:454` |
| `RankDB.lua:638` → `RankDB.lua:648` | `function RankDB.PruneStaleRecords(...)` at `:648` |
| `RankBrowser.lua:192` → `RankBrowser.lua:379` | `local function formatRelativeTime(timestamp)` at `:379` |
| `RankSync.lua:1335` → `RankSync.lua:1344` | `local function syncNow(force)` at `:1344` |
| "matching `LB_TOP` / `LB_MY_RANK_ARROW`, which always spelled them correctly." → "matching `LB_TOP` / `LB_MY_RANK_ARROW` in `enUS` — the ten translated locale files still carry a third byte sequence (`\226\152\160`) for `LB_TOP`, which is a separate defect from the sort hint and is not fixed here." | **This was false.** `Locale/enUS.lua:209` carries `\226\150\178` (▲, U+25B2). All ten translated files carry `\226\152\160` — U+26A0 ⚠ — for `LB_TOP` (`deDE.lua:206`, `esES.lua:206`, `esMX.lua:206`, `frFR.lua:206`, `itIT.lua:206`, `koKR.lua:206`, `ptBR.lua:206`, `ruRU.lua:206`, `zhCN.lua:206`, `zhTW.lua:206`). The claim now states the truth and flags the defect. |
| "The focused leaderboard harness grew from 80 to 136 checks at the time (163 at this revision, with the later Stage-3/4 display pins)." → "…at the time, and the later Stage-3/4 display pins and the Batch-7 label pins grew it further." | 163 is stale for the shipped file: `TacoTip_Extras/Tests/harness/rankbrowser_test.lua` has 272 `check()` call sites, several inside loops, so the runtime count is higher. The historical "80 to 136" is kept; the false "at this revision" number is gone. |

### D. Main `README.md`

| Claim (before → after) | Evidence |
| :--- | :--- |
| Directory tree root `TacoTip_Forever/` → `TacoTip/` | There is no `TacoTip_Forever/` directory in the tree; the next paragraph already said "This addon is shipped as `TacoTip/TacoTip.toc`". |
| `luacheck TacoTip_Forever/` → `luacheck .` | Same: the directory does not exist, so the documented command could not run. The changelog already documents the working command (`luacheck .` from the repository root). |
| "To run the whole matrix (59 invocations across all five clients, …)" → "(70 invocations …)" | `Tests/harness/run_all.sh` runs 70 invocations (1+1+1+1 detect/locale/font/textures + 10 load + 8 options + 20 settings + 2 file-scope + 1 fileguard + 1 batch2 + 1 batch4 + 5 batch8 + 5 gearscore + 5 tooltip + 5 taint + 3 talent_check). The harness README already says 70. |
| "Full detail, with file and line for every claim, is in [CHANGELOG.md](CHANGELOG.md)." → "Full detail is in [CHANGELOG.md](CHANGELOG.md)." | Rule-5 alignment: the player-facing "What's New" section must carry no file:line/process vocabulary. The changelog still carries the file:line detail; only the pointer changed. Matches the 0.8.3 / 0.8.1 / 0.8.0 sections. |

### E. `Tests/harness/README.md`

| Claim (before → after) | Evidence |
| :--- | :--- |
| "asserts **all 66 settings are reachable" → "all 68 settings are reachable" | The `DEFAULTS` table in `options.lua:127-201` declares 68 keys (lines 128–191 = 64, plus 197–200 = 4). `locale_override = nil` creates no key in Lua, so `GetDefaults()` yields 67; `settings_test.lua:626-651` recovers the nil-valued one from the source text and asserts the count is `>= 60`, and `settings_test.lua:1110` asserts every declared setting is reachable. 68 is the declared total. |
| Mock-fidelity row for `C_Item.GetItemInfoInstant(link)`: "mocked as `nil` in every harness" / "**the mock was accidentally faithful to the broken production read**" → "**was mocked as `nil` in every harness** -- accidentally faithful to the broken production read; the production read is namespace-first now and `tooltip_test` pins the ID (see the `main.lua` cold-path item request)" | `Tests/harness/tooltip_test.lua:654` now mocks the namespaced `C_Item.GetItemInfoInstant` to return the item ID (and `:3808-3813` pins it); the other harnesses mock only the bare global. The old text described a state the Batch-7 fix removed. |

---

## (b) Left alone, and why

1. **`README.md` "What's New in 0.8.4" — "Fast mouse-outs no longer lose the tooltip on slow-to-load setups."**
   The 0.8.4 change behind it is the pcall guard on the instant-fade mouseover
   probe (`main.lua:1214-1245`, used at `:4386` and `:4396`). Pre-fix, a raise
   there aborted the `UPDATE_MOUSEOVER_UNIT` handler; the handler is wrapped in
   `safeCall` (`main.lua:4451-4453`), so the changelog's own wording is
   "can no longer **silently kill the branch**", and the base-release entry says
   "no behaviour change intended". "Lose the tooltip" is a defensible
   player-language reading of "the branch is killed", but it is not what the code
   does to the tooltip itself. **Ambiguous → left as-is, reported.** If the
   operator wants it tightened, the precise replacement is:
   `Fast mouse-outs no longer break the add-on's own handling on slow-to-load setups,`

2. **`README.md` — "the player-name line is 1px smaller".**
   `main.lua:886` sets `TOOLTIP_NAME_FONT_SIZE_DELTA = 1` (the name line is
   body **+1px**, reduced from +2). "1px smaller" is true against the previous
   release and misleading if read as "smaller than the body text" — the 0.8.2
   section of the same README says "2pt larger than body text".
   **Ambiguous → left as-is, reported.** Recommended:
   `Small polish: the player-name line is 1px smaller than it was,`

3. **`README.md` — "how long ago the last inspect problem happened".**
   The diag prints `last error at (uptime)` = `st.lastErrorAt`
   (`main.lua:3978`), i.e. the uptime **stamp** of the raise, not an elapsed
   "ago" value; the diag prints no session uptime to subtract from.
   **Ambiguous → left as-is, reported.** Recommended: `…and when the last inspect problem happened.`

4. **`CHANGELOG.md` `[0.8.4]` — Batch 3's Retail-bracket paragraph
   (`gearscore.lua:175-196`).**
   That paragraph is explicitly superseded by Batch 5 ("This supersedes the
   Batch 3/4 Retail paragraphs above, which stay as history") and describes a
   `BRACKET_SIZE` of 2000 that the shipped code does not have
   (`gearscore.lua:179` = 1000). Left untouched as history; the coordinate is
   stale for the same reason the behaviour is.

5. **`CHANGELOG.md` `[0.8.4]` — intermediate harness totals (54/54, 58/58,
   59/59, 64/64).**
   These are the totals as of the batch they belong to, and the section's final
   "Verified" line carries the shipped numbers (**70/70**; Extras **42
   invocations: 42 passed, 0 failed**). Left as history.

6. **`CHANGELOG.md` `[0.8.4]` — "0 warnings / 0 errors in 87 files" (root).**
   Environment-dependent (the count sweeps the whole workshop tree, including
   `OLD/`, 22 files). A static count of the tree gives 88 `.lua` files, one off
   and not reproducible without running luacheck. The sibling claim
   "`cd TacoTip_Extras && luacheck .` → 0/0 in 26 files" **is** exactly right
   (12 add-on + 11 locale + 3 harness = 26). Left.

7. **`TacoTip_Extras/CHANGELOG.md` — the Stage 2/3/4/5 pin counts (39 / 28 /
   39 / 17).**
   Each of those sentences enumerates a *subset* of the pins, and the count
   matches that enumeration as written. The harnesses have since grown inside
   the same release, so the absolute counts are no longer the file totals, but
   the sentences are not false. Left.

8. **`TacoTip_Extras/README.md` — "Twelve scenarios per interpreter".**
   True of the load matrix (12 entries in `TacoTip_Extras/Tests/harness/run_all.sh:93-106`);
   the script also runs two leaderboard-browser invocations per interpreter
   (`:123-124`), so 14 per interpreter / 42 total. The README states no total,
   so it is incomplete rather than wrong. Left.

9. **`TacoTip_Extras/README.md` — `status: unreleased` + "Not yet released. The
   add-on is unreleased under its current packaging; the CurseForge listing does
   not exist yet."** (Known limitations) versus the same file's
   `curseforge_id: 1741092`, `project_url: …/tacotip-extras/preview`, the
   "this add-on" preview link, and the main README's "Companion App" link to
   the same URL. **Operator decision, not a code truth** — it needs a human to
   say whether Extras 1.2.3 is being published now. Left, reported as the top
   release-facing item. (CurseForge itself returns HTTP 403 to a scripted GET,
   so the listing's existence could not be confirmed from here; the linked
   banner image `media.forgecdn.net/attachments/2065/485/2-png.png` does resolve,
   200 `image/png`.)

10. **Front matter `requires:` / `optional:` (both READMEs).**
    The main README lists `LibStub`, `CallbackHandler-1.0`, `LibDetours-1.0`,
    `Pawn`, `LibSharedMedia-3.0`, `SharedMedia` under `requires:`, while
    `TacoTip.toc:9` declares all six as `## OptionalDependencies:` — and the
    first three are **bundled** in `Libs/`, so a user cannot install them
    separately. The front matter has no consumer in this repo (no script reads
    `curseforge_id`), and the TOC is what CurseForge actually reads, so the
    intent of the field is unclear. Left, reported.

11. **Code comments that cite stale lines** (out of scope — code, not docs):
    `options.lua:364` points the anchor slash path at `options.lua:441-459` and
    `main.lua:2916-2917` (actual: `options.lua:630-642`, `main.lua:3364-3371`);
    `Tests/harness/run_all.sh:7` still says
    `bash TacoTip_Forever/Tests/harness/run_all.sh`.

---

## (c) What was verified and found TRUE (no change)

Main README, "What's New in 0.8.4", bullet by bullet:

- **Scan-nearby checkbox** — created on the Tooltips page (`options.lua:2377-2392`),
  wired to the library's `SetScanEnabled` (`LibForeverInspector.lua:5366-5368`);
  the checkbox follows `lib.scanEnabled`, and Refresh reconciles it
  (`options.lua:2749-2753`). The library's own scan gate is `if (not
  lib.scanEnabled) then return end` (`LibForeverInspector.lua:5293`) — the
  background scan only; hover/target inspection is a separate path.
- **No wrong spec** — `GetSpecialization` returns `nil` for an uncached or
  spec-less unit (`LibForeverInspector.lua:5470-5489`); the tooltip gates the
  whole talents block on `if (spec1)` (`main.lua:2299-2300`).
- **Pawn mid-session** — module no longer returns early; `WasAvailableAtLoad`
  /`IsAvailable` (`pawn.lua:122-123`); the checkbox reads the live state
  (`options.lua:2740-2744`); the render gate stays on the file-scope snapshot
  (`main.lua:161-168`, `2417`); diag names the gap (`main.lua:4141-4143`).
- **Hunter scoring** — the gate is a per-call `getPlayerClass()`
  (`main.lua:337-343`, used at `:2842`).
- **Power-bar fallback** — a failed `RegisterUnitEvent` triple falls back to
  plain events (`main.lua:2612-2633`), counted as `power-bar unit-reg fallbacks`.
- **Panel/options failure surfacing** — one chat line per distinct failure
  (`options.lua:86-99`) and the same list in `/tacotip diag` problems[]
  (`main.lua:4145-4152`).
- **Tooltip edge cases** — the terminal `UpdateTooltip`/`SetUnit` failure is
  reported (`main.lua:1550-1564`); a load that stops early names its stage
  (`main.lua:18`, `:50`, diag `:4200`).
- **Diag truthfulness list** — `queue dropped (overflow)` (`:4001`),
  `not-ready scores hidden (pending)` (`:3909`), `no-tooltip`/`no-source`/
  `unresolved` (`:3915-3917`), `last error at (uptime)` (`:3978`).
- **1px name line** — `TOOLTIP_NAME_FONT_SIZE_DELTA = 1` (`main.lua:886`).
- **Interface band** — `TacoTip.toc:1` and both READMEs carry exactly
  `11509, 20506, 38002, 16001, 120105`.
- **Character/inspect pane refresh** — `CharacterFrame`/`InspectFrame` `OnShow`
  hooks (`main.lua:3567-3572`, `:3740-3746`), one inventory walk per pane open,
  plus the pending→ready repaint budgeted to one (`main.lua:1493`, `:1537-1539`).
- **Instant fade** — a client with no `GameTooltip.FadeOut` gets the checkbox
  **disabled** with a plain-English reason (`options.lua:2969-2976`), and the
  diag prints the mode (`:4220-4221`).

Extras README:

- **Rank line** — `GS Rank: #14 [#2 Warrior]`; label in all 11 locale files
  (`TOOLTIP_LABEL_RANK`); white brackets, class name in class colour, class
  icon in Compact with a class-name fallback (`Tooltips.lua:681-715`).
- **Gear panel** — 17 slot rows (`RankBrowser.lua:1090-1106`), each label taken
  from the client's own `INVTYPE_*` string with an English fallback
  (`:1136-1160`), the hand row on `INVTYPE_HAND` (not `INVTYPE_HANDS`), the
  back row on `INVTYPE_CLOAK`; rows render the real item link
  (`slotValueText`, `:1169-1193`).
- **Gear-panel empty state** — fresh session → persisted IDs + last-synced note
  → `GEAR_NOT_SCANNED`; `GEAR_DATA_UNAVAILABLE` when the session saw the player
  but yielded no gear (`RankBrowser.lua:1478-1500`).
- **Leaderboard features** — 7 slash aliases (`RankBrowser.lua:2495-2501`),
  whole-realm ranking, opens centred on your own row, class dropdown + guild
  box + live search, sortable `GEARSCORE`/`iLVL`/`LEVEL`/`LAST SEEN`
  (`RankBrowser.lua:87-93`), `▲ Top` / `▼ My Rank`, `Up`/`Down`/`Enter`,
  `Comfortable rows` 26px→32px (`:23`, `:1924`), personal standing footer
  (`LB_FOOTER_STANDING`, `Locale/enUS.lua:255-256`).
- **Scan button** — one shared scan from the leaderboard header
  (`RankBrowser.lua:2253`) and the Options page (`Options.lua:1315`), with the
  progress rail fed by `Scanner.GetProgress()` (`Scanner.lua:1116`).
- **PvP lines** — Era/TBC/Wrath only; the modern pair is gated out by
  `C_PaperDollInfo.GetInspectRatedBGData` (`RankBrowser.lua:349-357`).

Metadata:

- `curseforge_id` 1555962 / 1741092 match both TOCs; `clients`,
  `interfaces`, `version` (0.8.4 / 1.2.3), `author`/`maintainer`, `license`,
  `project_url`, `tags`, `updated` (2026-10-18 = the changelog release date)
  all match the shipped TOC and changelog.
- The in-game suite is 11 suites (`Tests/TacoTip_Forever_Tests.lua`, 11
  `WoWUnit(...)` declarations) — the README's list is exact. There is no
  separate in-game-suite document in the tree; the main README's
  "Verification & Testing" section is it.
- `luacheck` 0/0 in 26 files for Extras — exact.

---

## Verdict

**PUBLISH VERDICT: DOCS SHIP** — with three player-facing phrasings in
`README.md` flagged for an operator decision (§b items 1–3) and one
release-status question on the Extras README (§b item 9).

No claim that is demonstrably false was left in place. No code, test, TOC,
version or file outside the five permitted documents was modified.
