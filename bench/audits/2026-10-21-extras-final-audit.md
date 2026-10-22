# TacoTip Extras 1.2.3 — final audit before publish

2026-10-21. Scope: the whole shipped Extras tree (12 Lua files, 11 locales,
`TacoTip_Extras.toc` v1.2.3), audited to the same bar as the main add-on:
load safety on all five clients, per-branch API truth from the FrameXML mirror,
state safety, and whether any shipped feature can silently do nothing.

**Method:** `origin/<branch>` reads of `/home/sam/wow-ui-source`, per branch —
never family-level, never a subagent. Blizzard's own unguarded call counts as
proof that an API exists. The classic generated API docs are an incomplete set,
so "absent from the docs" was **not** treated as absence.

## Verdict

**No load-abort, no unguarded client API, and no silent dead feature found in
shipped code.** The one behavioural question this pass opened — the PvP
"modern surface" marker — was **resolved during the audit** and is now decided
by client family (§2). Three test-sufficiency gaps remain (§3); none blocks the
1.2.3 upload.

## 1. What was checked, and on what evidence

| surface | finding | evidence |
| :--- | :--- | :--- |
| file-scope execution | only an event frame + six `/` command aliases run at load; nothing that touches a branch-specific API | `Core.lua:1570-1571`, `RankBrowser.lua:2992-3014` |
| `HookScript` | every site goes through `hookIfDeclared` (`HasScript` + `pcall`) or a `pcall`; no unguarded hook | `Frames.lua:91-105`, `Options.lua:628-633`, `Tooltips.lua:1694-1728` |
| `hooksecurefunc` | capability-gated, `pcall`-wrapped, targets the add-on's own methods | `Frames.lua:1426-1433`, `TacoTipAdapter.lua:742` |
| frame templates | only four, all present on all five branches: `UIPanelButtonTemplate`, `UIPanelCloseButton`, `UIDropDownMenuTemplate`, `FauxScrollFrameTemplate` | 4th-arg sweep of every `CreateFrame` |
| `C_AddOns` | exists on **all five** (125 uses on classic_era alone); `GetAddOnMetadata`/`IsAddOnLoaded` exist too, so the primary path runs and the globals are a real fallback | per-branch usage counts |
| `C_AddOns.GetAddOns` | used by Blizzard on **none** of the five, so the Extras probes it and falls back to a global sweep | `TacoTipAdapter.lua:306-320` |
| item APIs (`GetItemNumSockets`, `GetDetailedItemLevelInfo`, `IsItemDataCachedByID`, `RequestLoadItemDataByID`, `GetItemStats`) | every call is `type(...) == "function"`-gated and `pcall`-ed; `GetItemStats` absence is a tested path | `Scanner.lua:229, 591-595, 640-675, 967` |
| `C_Item` itself | indexed only after `type(C_Item) ~= "table"` — safe even where the namespace is absent | `Scanner.lua:639` |
| spec / honor / PvP capture | `rawget` + `type` + `pcall`; degrades to `0`, never invents an encoding | `Scanner.lua:296-360` |
| group APIs | the classic/modern split is not used at all (no `GetNumGroupMembers`/`GetNumSubgroupMembers`); only `IsInGroup`/`IsInRaid` | grep |
| options registration | no `Settings.*` and no `InterfaceOptions_AddCategory`: the Extras hosts its **own** window, so the split cannot be got wrong | `Options.lua` (`Open`/`Toggle`), no registration sites |
| minimap button | parented to a guarded `_G.Minimap`, no template, frame level guarded | `Minimap.lua:179-205` |
| backdrop panels | `CreateFrame(..., "BackdropTemplate")` under `pcall`, with the mixin applied by hand if the template is missing | `RankBrowser.lua:1566-1590` |
| font objects | shipped code uses only names that exist on all five (`GameFontNormal`, `GameFontNormalLarge`, `GameFontHighlight`, `GameFontHighlightSmall`, `GameFontDisableSmall`) | per-branch XML counts |
| slot frames | `CharacterRangedSlot`/`InspectRangedSlot` do **not** exist on live; `frameEdge` is nil-tolerant and the bounds fall back when they invert | `Frames.lua:651-710`; live XML count = 0 |
| saved variables | absent / pre-1.0.0 name / fresh / `schema == 1` / `schema == 2` / future schema all handled; a future schema is copied, forced to `equipmentDisplay = Disabled`, and **never written back** | `Core.lua:494-537` |
| locale parity | **154 content keys × 11 locales, zero missing, zero extra, zero code-orphans** | key-set comparison + code-reference sweep |
| addon messages | both shapes (`C_ChatInfo.*` and the legacy globals) under `pcall`; own prefix `TACO_GS_SYNC`, never the main add-on's `R;2` wire | `RankSync.lua:10, 96-99` |
| scoring | delegates to the main add-on's `TT_GS` through **capability probes**, never a copied formula | `TacoTipAdapter.lua:52-60`, `probeCapabilities` |
| version gate | `MINIMUM_TACOTIP_VERSION = {0,8,0}`; 0.8.4 satisfies it; an older TacoTip is refused with a named reason | `TacoTipAdapter.lua:44, 560-610` |
| `CanInspect` / `NotifyInspect` | **never called** by the Extras, so the one-argument frozen rule cannot be broken here | grep |
| reasons surfacing | a refused surface prints its reason once, and every counter is in `/ttgsdebug` | `Core.lua:1355-1440` |

## 2. RESOLVED — the PvP marker now uses client family, not an API probe

`Scanner.modernRatedSurfacePresent()` and `RankBrowser.pvpLinesOf()` used
`C_PaperDollInfo.GetInspectRatedBGData` to decide "modern client". The code's
own comment marked that `[A] confirm the marker's absence on the classic family
in game`.

**Why it was wrong.** The marker asks whether an API *function* exists, not
whether the client renders rated-BG data. The operator's own statement — *"there
is no rated bg on classic era"* — is the feature truth, but the engine can still
expose the stub, and a stub would make a classic client look modern and
**silently zero the honor rank and arena fields** on the whole classic family.

The mirror cannot settle a modern client's API surface by absence either,
because these branches ship **dead game-type variants**: `GetArenaTeam`'s
classic uses are in `Classic/` files gated `[AllowLoadGameType tbc, wrath,
cata]`, and live's `GetPVPRankInfo` uses are in
`Vanilla/InspectHonorFrame.lua`, gated `[vanilla]`. So neither "used on branch
X" nor "unused on branch Y" is a statement about the loaded client. That is the
method correction this audit produced.

**Fix, decided with the operator: identity decides the family.**
`Core.IsClassicFamilyClient()` reads the vendored library's project identity —
`IsClassic`/`IsTBC`/`IsWotlk` for the classic family, the mainline pair
otherwise (Retail and WoW Forever share `WOW_PROJECT_MAINLINE`). Then
`Core.UsesModernPvPSurface()` composes the rule:

1. identity readable → classic family is **not** modern, mainline is;
2. identity unreadable → the rated-BG capability probe, i.e. the previous
   behaviour, so nothing regresses where the inspector cannot answer.

One implementation, called by both the scanner and the leaderboard (each keeps
a five-line fallback wrapper that is unreachable in a normal load). The
`[A]` open item is gone from the scanner's comment.

**Revert-to-fail proof** (the API-only marker restored, harness copy):

    FAIL  classic identity wins over the modern API stub (arena renders)
    FAIL  mainline identity hides the synced rating even without the API

— the old marker lost the arena line on a classic client *and* leaked it on a
mainline one. Both pins live in `rankbrowser_test.lua`'s PvP block, and the
existing two scenarios still pass through the capability fallback.

**Visible in game:** `/ttgsdebug` now prints
`client-family=classic|mainline|unknown pvp-surface=classic|modern`. `unknown`
means the identity fallback decided, so the line states which rule ran instead
of leaving it to trust.

## 3. Test-sufficiency gaps (no shipped defect; the suite cannot see these)

| gap | why it matters | state |
| :--- | :--- | :--- |
| `C_AddOns` absence is never exercised | the fallback is real code and the primary path is proven on all five, so risk is low — but the fallback itself has no pin | open |
| `C_SpecializationInfo` and the honor surfaces are not mocked at all | spec capture and the honor/arena path are unexercised; both degrade to `0` by inspection | open |
| a future-schema DB (`schema > 2`) is never seeded | it is the one branch that must not clobber user data; correct by inspection, unproven by test | open |
| the Extras' mock defines `GameFontHighlightSmallWhite`, which **no client has** | harmless today (shipped code never asks for it), but it is the same over-declaration class that hid the frame-script defect — a mock that invents client objects cannot catch a bad name | recorded |

## 4. Recorded, not changed

- **A future-schema DB runs on a copy, so settings writes do not persist.**
  That is the right call (a downgrade must not clobber a newer profile), but it
  is silent: the player changes a setting, sees it apply for the session, and
  loses it on `/reload`. Unreachable in 1.2.3's own data (`schema` max is 2), so
  it is not a release blocker; it needs a one-time chat line when a future
  schema is detected.
- **`InstallEquipmentDisplayDefaults`-era naming and the two spellings of
  `show_server_rank`/`showServerRank`** are intentional and documented in
  `Core.lua`; both are defaulted and read as "OFF if either says false".

## 5. What this audit did not find

- no file-scope statement that can abort the load on any branch;
- no unguarded `HookScript`, `hooksecurefunc` or `SetScript` on a Blizzard frame;
- no template or font name that is missing on a branch;
- no branch-split global called without a probe (`GetNumGroupMembers`,
  `GetArenaTeam*`, `C_Container.*` are not used at all);
- no locale gap in either direction;
- no reimplementation of the gearscore formula, the wire format, or the
  saved-variable shape.
