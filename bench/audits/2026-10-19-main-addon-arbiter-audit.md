# Deep MAIN-addon audit — API parity & production readiness (2026-10-19)

**Placement note:** the reviewing session had no file-write or shell tools; filed by the orchestrator from its inline handoff (desk `main-arbiter`, agent `main-arbiter`, run_id `arbiter1`) plus the addendum it delivered inline. **Verdict: SHIP-WITH-FIXES.** No CRITICAL. Two MEDIUMs and several LOWs beyond the 0 CRITICAL / 4 HIGH already handled in Batch 6.

**Method.** Every Blizzard API the addon calls was checked against `/home/sam/wow-ui-source` on the five branches (`origin/classic_era`, `origin/classic_anniversary`, `origin/classic_titan`, `origin/forever`, `origin/live`). Presence is proven by an upstream consumer call site or a generated-API-doc entry; absence by a whole-tree sweep on the classic family (the reviewing session's checkout is the complete classic-family tree) plus targeted probes on live/forever. The orchestrator independently re-verified the branch-sensitive claims below with `git show` / `git grep`.

## Client-fact verification (orchestrator-confirmed, all five branches)

| Fact | Result |
|---|---|
| `C_Item` namespace, `C_Item.GetItemInfo`, `C_Item.RequestLoadItemDataByID`, `C_Item.IsEquippableItem` | present on all five; `GetItemInfo`'s 19-value shape identical everywhere (the addon's positional destructuring is correct on all five) |
| `C_Item.GetItemLinkByGUID` | modern pair only — `main.lua:2610` already guards it |
| `Enum.TooltipDataType`, `TooltipUtil` | modern pair only — both guarded at every call site |
| `GameTooltip.FadeOut` | **live + forever only**; absent from the whole classic family (only `PhotosensitivityWarningFrame` and `EncounterTimeline` define a `FadeOut`) → see N2 |
| `Settings.RegisterCanvasLayoutCategory` / `RegisterCanvasLayoutSubcategory` / `RegisterAddOnCategory` | present on all five (`Blizzard_Settings.lua:161/:165/:133` classic, `:162/:166/:134` live/forever) |
| `StaticPopup1..4` | **exactly four named frames on all five branches**, no fifth → `MAX_STATIC_POPUP_DIALOGS = 4` is correct everywhere |
| `GameMenuFrame` | `toplevel="true" frameStrata="DIALOG"` on all five; `SettingsPanel` = `toplevel="true" frameStrata="HIGH"` on all five → the Extras browser's `FULLSCREEN_DIALOG` + top-level choice is correct on every client |
| `CharacterModelFrame` | classic family only; absent on live/forever → the addon's `_G.CharacterModelFrame or _G.PaperDollFrame` host resolution is required, not optional |
| `CharacterFrame` / `InspectFrame` | `hidden="true"` on **all five** → their `OnShow` fires when the player opens the pane |
| `PaperDollFrame` / `InspectPaperDollFrame` | **no `hidden` attribute on any branch** → their `OnShow` never fires (the hooks on them are dead) |
| `GetPlayerInfoByGUID` | return #2 is `englishClass` on all five → the addon's indexing is correct (the reviewing agent withdrew its own candidate finding here) |
| `GetActiveTalentGroup` | no classic consumer, but the library tries `C_SpecializationInfo.GetActiveSpecGroup` first — candidate finding withdrawn, the library is correct |
| `CanInspect` | absent from the generated API docs on all five; every call site is guarded and the probe returns nil when absent → behaviour safe, but the library's doc claim is unsupported (N5) |

## Findings

- **N1 (MEDIUM) — `main.lua:2736` read the bare global `GetItemInfoInstant`.** The bare global exists only as a `Blizzard_DeprecatedItemScript` alias on the three Classic branches; that file is **absent on `origin/forever` and `origin/live`**, so `itemID` was nil and the cold-path item-data request never fired on Retail/Forever (the 0.5 s repaint timer masked it). **FIXED in Batch 7** — namespace-first resolution (`C_Item.GetItemInfoInstant`), first return is the item ID (`Blizzard_AuctionHouseSharedTemplates.lua:366` on classic_era; `ItemMixin:GetItemID`, `Item.lua:100`), bare global only as a fallback; pinned (one request carrying a numeric id on a client without the bare global).
- **N2 (MEDIUM) — `instant_fade` is inert on the Classic family.** `GameTooltip.FadeOut` does not exist there, so the toggle changes nothing while still being offered and settable, and `TT.InstantFadeMode` (which records the degradation) is never printed by `/tacotip diag`. **→ Batch 8:** gate the checkbox on the API being present and print the mode in diag.
- **N4 (LOW) — three of the six `LoadAddOn` targets do not exist on the client they are probed for** (`Blizzard_Settings` absent on the three Classic branches; `Blizzard_SettingsDefinitions`, `Blizzard_OptionsUI`, `Blizzard_InterfaceOptions` absent on all five). The block is guarded, so it never fires today, but if it ever did, `/tacotip diag` would report "options load failures" for addons that were never meant to exist on that client. **→ Batch 8:** distinguish "not applicable on this client" from "failed to load".
- **N5 (LOW, doc) — the library claims `CanInspect` is "documented with a single argument on every branch"**; it is absent from the generated API docs on all five. Behaviour is safe (every call site guarded), but the recorded reasoning is not evidence-backed. **→ Batch 8:** correct the comment.
- **N6 (LOW) — `C_Map.GetBestMapForUnit` is dead on the classic family**, so the "target is on another map" suppression never applies there. Guarded, not broken; needs a comment so a maintainer does not assume it works everywhere. **→ Batch 8.**
- **H1 (HIGH, user-visible) — the character/inspect pane overlay can read `0`.** `PaperDollFrame` and `InspectPaperDollFrame` carry no `hidden` attribute on any branch, so the `OnShow` hooks on them never fire; the overlays refresh only at login and on `PLAYER_EQUIPMENT_CHANGED`. `CharacterFrame` and `InspectFrame` DO carry `hidden="true"`, so their `OnShow` fires on every pane open. **→ Batch 8:** hook the real panes, refresh once per open, and refresh when the player's own score becomes ready. Guardrails from the 0.7.9 / 0.8.2 / 0.8.3 history: never index `CharacterModelFrame` unguarded (0.7.9 Retail crash), one inventory walk per refresh (0.8.2's eight-walk bug), no `CanInspect(unit, true)` anywhere (0.8.3 `showError`), and no change to the guild/level line-index ownership proof (0.7.9 "another addon's line erased").
- **H2 — HunterScore line colour.** **RESOLVED BY THE OPERATOR: the HunterScore line intentionally uses the GearScore band colour** — it is read as the hunter equivalent of the iLvl line. Not a defect; no change. Recorded so the next audit does not re-raise it.

## Operator decisions recorded

- **D12 (gear-panel slot-label source):** the operator chose **"get the label from wherever you can"** — the client's own `INVTYPE_*` strings first (Blizzard ships them translated in every language the game ships, which is the whole point of the feature), with the addon's English fallback when a global is absent. Batch 7 fixes the one bad name (`INVTYPE_HANDS` → `INVTYPE_HAND`, verified absent on all five branches) and pins all 17 names in the harness so a typo can no longer ship silently.
- **Retail GearScore bracket:** held at the shared `1000` pending a live screenshot (operator decision, supersedes the Batch 3/4 experiments).
- **H2 tri-state** (`DoInspect` true-means-queued): still open — needs the operator's contract call.
- **M7 / L-NEW1 (ruRU MONK/DEMONHUNTER/EVOKER spec names):** still German/English placeholders under the ruRU locale. Needs a translator; no Russian strings were invented.
