# Test-sufficiency audit — MAIN + Extras (2026-10-19)

**Placement note:** reviewing session had no file-write or shell tools; filed by the orchestrator from the agent's inline handoff (desk `proctor-audit`, agent `proctor-audit`, run_id `proctor2`). The reviewing session could not read `/home/sam/wow-ui-source` directly and reached the mirror through the checked-out `origin/live` tree; **the orchestrator re-verified the branch-sensitive claims below with `git show` / `git grep` on all five branches** and marks them VERIFIED.

## Mock-fidelity findings

| # | Sev | Mock | Client truth | Verdict |
|---|---|---|---|---|
| M1 | 7/10 | `Tests/harness/tooltip_test.lua:1284` — `GT.GetUnit` returns a **third** value (a GUID) | The engine returns **two** (`name, unit`): `Blizzard_PTRFeedback/Blizzard_PTRFeedback_Tooltips.lua:87` destructures two; no Lua `GetUnit` definition exists under `Blizzard_GameTooltip`. The sibling `TooltipUtil.GetDisplayedUnit` correctly returns three (`TooltipUtil.lua:40`), which is why the mistake was invisible. | **False-confidence pin.** `main.lua:1058` reads the third value as `guid` and branches on it at `:1068-1071` — a branch that cannot execute in the real client, while the real Classic resolution chain (`GetUnit` token → `IsUnit` disagreement → `GetOwner` → `"mouseover"`) is never driven. The mock is installed on exactly the three Classic clients. → Batch 7 (mock made faithful + real chain pinned). |
| M2 | 6/10 | `Tests/harness/options_test.lua:400-407` — `Settings` namespace mocked with a phantom `self` | `Blizzard_Settings_Shared/Blizzard_Settings.lua:161/:165/:133` are plain functions on a namespace table, called with a dot. Production calls (`options.lua:783/785/724`) match the client exactly. `settings_test.lua:526-536` mocks the same API with correct arity/order. | **Wrong mock, zero coverage** — the `registered` table is never asserted by any check (6 grep hits, all definitions). → Batch 7. |
| M3 | 5/10 | `GetItemInfoInstant` mocked as `nil` in every MAIN harness | The live tree calls **only** `C_Item.GetItemInfoInstant` (0 bare call sites on all five branches; 11–21 namespaced per branch). `C_Item.GetItemInfoInstant` returns the **itemID first** (`Blizzard_AuctionHouseSharedTemplates.lua:366` on classic_era; `ItemMixin:GetItemID`, `Item.lua:100`). | The `nil` mock is *accidentally faithful to the broken production state* on Retail/Forever, which is why P1 is invisible. |
| M4 | 5/10 | `UnitClass` mocked with 2 returns on all five clients | The live client returns **three** (`localizedClassName, classToken, classID` — `Blizzard_SharedXML/UnitUtil.lua:80-83`, `Blizzard_ClassMenu.lua:7`, `ClubFinder.lua:882`). | No current impact (production reads 2), but the file-scope capture at `main.lua:189` makes a per-client arity gap structurally invisible. |
| M5 | 4/10 | `GetSpecializationInfoByID` mocked with 4 returns | The real returns 7–8 (`ClubFinder.lua:599`, `LootFrame.lua:706`). | No impact — production reads positions 2 and 4 only. |
| M6 | 4/10 | `FauxScrollFrame_Update` mocked with a return value | The real function has **no return** (`SecureScrollTemplates.lua:158-222`; the file's only returns are at 152/154/224/237). | No impact — production discards it. |

**Mocks verified FAITHFUL (positive):** `GetClassAtlas` (reproduces `SharedConstants.lua:44` exactly, including no lowercasing); `C_Item.GetItemInfo` (11-value order matches `ItemButtonTemplate.lua:187` for every position the production reads — the suite's most important mock, and it is correct); `TooltipUtil.GetDisplayedUnit`; `FauxScrollFrame_GetOffset`/`_SetOffset`/`_OnVerticalScroll` (exact, including the `math.floor((value/itemHeight)+0.5)` rounding and the 4th `updateFunction` parameter); `settings_test.lua`'s `Settings` mock; `StaticPopup_Show` signature; `CheckInteractDistance` boolean-first; the `ItemMixin` method set (a safe subset of `Blizzard_ObjectAPI/Classic/Item.lua`).

## Production defect surfaced by the mock audit — P1 (orchestrator-verified on all five branches)

**`main.lua:2736` reads a bare global `GetItemInfoInstant` that does not exist on Retail or WoW Forever.**
- Mirror evidence: Blizzard's own code makes **0** bare calls on every branch; the bare global exists only as a deprecated alias on classic_era / classic_anniversary / classic_titan (`Blizzard_DeprecatedItemScript/Deprecated_ItemScript.lua:10`), and `Deprecated_ItemScript.lua` is **absent on origin/forever and origin/live**.
- Consequence: `itemID` is nil on Retail/Forever → the cold-path `RequestLoadItemDataByID` never fires there. The 0.5 s generation-bounded repaint timer masks it (degraded, not broken). The comment four lines above (`main.lua:2721-2725`) documents exactly this mistake for `RequestLoadItemDataByID` — the same branch then repeats it for the other API.
- Fix (Batch 7): resolve the namespaced form at file scope, prefer it, fall back to the bare global only when `C_Item` is absent, take the **first** return as the item ID; pin one numeric-ID request on a client without the bare global.

## Harness integrity

- **HI-11:** the MAIN harness documents a mock-fidelity discipline (`Tests/harness/README.md`) but nothing enforces it — three audited mocks break rules the README itself states.
- **HI-12:** no harness asserts the *shape* of what it mocks; a contract test (`{api, realArity, mockArity}`, sourced from the mirror) would catch M1/M2/M4 mechanically. → queued as a follow-up lane.
- **Gap 5b (6/10):** no mock-fidelity contract test — every drift above was found by reading the mirror, not by the suite.
- **Gap 5c (5/10):** the mirror is not wired into the review process; client-behaviour claims live only as prose.

## Operator in-game checklist (the part the harness cannot prove)

1. **Classic Era — hover a hostile NPC.** Confirm the tooltip does **not** paint the mouseover player's class colour (the real Classic resolution chain is untested offline; the harness mock returned a GUID the engine never returns).
2. **Retail / WoW Forever — hover an uncached item.** Confirm its data (GearScore / iLvl) arrives within ~1 s. If the item is noticeably slower to populate on Retail/Forever than on Classic, that is P1's cold path.
3. Per client: open the game menu and quit (no `ADDON_ACTION_FORBIDDEN`); open the rank browser over the Settings menu; click a row and open the gear panel; compare a ~1400 GS tooltip colour with the same player's browser row colour.
4. Retail: confirm endgame character frames do not all read constant Artifact (the bracket is held at the shared `1000` by operator decision — screenshot decides it).
