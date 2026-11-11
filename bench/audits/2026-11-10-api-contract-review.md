# Unit / Item API contract audit - independent review (t12)

Reviewer: taint-reviewer (attempt 1, `ee890246-05b8-4364-8b9d-ba663b10fdc5`)
Date: 2026-11-10
Verdict: **PASS** - no counterexample found to the corrected contracts. Residual
risks are listed at the end as observations; none is reachable under the
documented contract, so none is a required fix.

Scope reviewed: the changes from t9 (`Libs/LibForeverInspector/LibForeverInspector.lua`),
t10 (`main.lua`) and t11 (`options.lua`, `gearscore.lua`, `pawn.lua`), plus every
remaining Unit*/Item* call site in those five files. No addon source was edited.

## 1. Method

1. Re-derived the contract for 60 call sites **directly from the client mirror**,
   not from the t8 ledger: `/home/sam/wow-ui-source` at
   `eac30af597e5aaa43a60f6675ef5fdcea100375f` = `1.60.1 (70790)`,
   `git branch -a --contains HEAD` -> `remotes/origin/forever` only.
   Blocks read from `Interface/AddOns/Blizzard_APIDocumentationGenerated/`:
   - `UnitDocumentation.lua` - UnitGUID :1241, UnitExists :1192, UnitIsPlayer
     :2271, UnitIsConnected :1855, UnitIsDeadOrGhost :1931, UnitIsUnit :2410,
     UnitInParty :1637, UnitInRaid :1683, UnitIsPVP :2225, UnitCanAttack :763,
     UnitLevel :2474, UnitClass :911, UnitName :2489, UnitRace :2925, UnitSex
     :3069, UnitPower :2732, UnitPowerMax :2801, UnitPowerType :2859,
     UnitPVPName :2601, UnitFactionGroup :1207, UnitGroupRolesAssigned :1318,
     UnitIsSameServer :2350, UnitDistanceSquared :1108, UnitIsVisible :2428,
     UnitIsOtherPlayersPet :2193, SetPortraitTexture :572.
   - `ItemDocumentation.lua` - GetItemInfo :626, GetItemInfoInstant :659,
     IsEquippableItem :1324, RequestLoadItemDataByID :1710,
     GetItemLinkByGUID :771, GetItemLink :756, GetItemID :551,
     IsItemDataCached :1505, IsItemDataCachedByID.
   - `PlayerLocationDocumentation.lua:11` (C_PlayerInfo.GUIDIsPlayer),
     `PlayerScriptDocumentation.lua:55` (CanInspect), `:114`
     (CheckInteractDistance), `:837` (GetPlayerInfoByGUID) - the auxiliary
     documented APIs the identifier scan surfaced beside the ledger.
   - `SecretPredicatesDocumentation.lua` - the semantics of every `SecretWhen*`
     flag used to judge the sites (`SecretWhenUnitIdentityRestricted` :141-146,
     `SecretWhenUnitComparisonRestricted` :133-138, etc.).
2. Independently enumerated every Unit*/Item* call site in the five files by
   identifier scan (plain calls, `pcall(Fn, ...)`, `_G.Fn`, file-scope aliases,
   ItemLocation methods) and compared the set against the ledger. The ledger's
   119 rows cover the same call set; no call site was missing. The scan found
   four documented auxiliary APIs the ledger does not row (GUIDIsPlayer,
   GetPlayerInfoByGUID, CanInspect, CheckInteractDistance); each was checked too.
3. Read **every one of the 37 diff hunks** in the five code files. This audit
   owns 5 LFI hunks, 15 main.lua hunks, 4 gearscore.lua hunks (2 functional) and
   3 options.lua hunks (25 functional hunks); the remaining 12 are
   `---@secret-guard` / `---@return` / formatting changes that were already in
   the working tree before the team started (mtimes 19:01-19:44; the
   `AGENTS.md` / `workshop.md` diffs describe that LSP pass). All of them are
   comment or whitespace-only at runtime.
4. Re-ran the red/green proofs rather than trusting the t13 report: the new
   contract pins fail on `git show HEAD:` copies (3 on main.lua, 8 on
   LibForeverInspector.lua) and pass on the fixed tree; full main suite green.

## 2. Adversarial checklist - result per category

| Target | Result |
| :--- | :--- |
| comparison / index / arithmetic / table key applied to a possibly-secret value | **None reachable.** Every changed hunk was walked; every remaining site where a Unit*/Item* return is later compared/indexed is secrecy-tested first. The one suspicious residual (main.lua:5340 classFilename used as a table key inside `CI:GetSpecializationName`) is unreachable as a *secret* because that branch also requires a non-nil `specIndex` derived from `guid`, and UnitClass and UnitGUID share the same `SecretWhenUnitIdentityRestricted` predicate: a secret classFilename cannot occur without a secret GUID, which leaves `guid = "<secret>"` and the branch is skipped (see observation O1). |
| possibly-secret unit token reaching a `SecretArguments = "AllowedWhenUntainted"` function | **None.** All bare calls use literal or generated tokens (`"player"`, `"target"`, `"mouseover"`, `"party"..i`, `"raid"..i`, `tooltipUnit.."target"`); every call whose token can be caller-supplied is either behind `isSecretValue` or behind a `safe*` boundary / `probe*` guard (LFI :160-202, :3386-3398, :3470-3479, :4780-4811, :5697-5735, :5780-5860; main.lua :309-396, :720-730, :946-955, :990-996, :1849-1855, :1904-1911, :3683-3690). |
| nilable return used before a `type(v) == "nil"` test | **Corrected where it mattered.** UnitGUID (`main:309-316`, LFI:100-107), `C_Item.GetItemLinkByGUID` (main:3899-3904) and `ItemMixin:GetItemID`/`GetItemLink` returns are nil-tested. Remaining truthiness tests are on documented `string` returns (`gearscore:274`, `pawn:212`, main:5192-5198): truthiness on a secret string is legal, and no comparison/index/arithmetic happens before the `isSecretValue` test. Noted as style inconsistency (O3), not a defect. |
| MayReturnNothing call treated as a nilable one | **No misuse.** GetItemInfo (main:2547, 3962, 6125; LFI:4202), UnitClass (main:915, 2945, 3021, 3982; LFI:1049, 3475), UnitRace, UnitPowerType, GetPlayerInfoByGUID and GetItemInfoInstant are all read through the pcall ok flag, an explicit nil test, or a nil-safe `select`/`and` chain. No site assumes a value exists. |
| `---@diagnostic disable` introduced | **None.** `git diff -U0 -- '*.lua' \| grep -E '^\+.*diagnostic'` is empty. Three pre-existing `inject-field` suppressions were **removed** from main.lua (comment-only change). Two pre-existing directives remain at LFI:3224 and LFI:4591 (also present at HEAD); see O4. |
| player-visible change | **None.** Every changed expression is an equivalence transform for non-secret values (guard additions are no-ops when `issecretvalue` is absent/false; `max ~= nil` -> `type(max) ~= "nil"` preserves both branches; the honor-rank and hunter checks are the same conditions split across two `if`s; the distance reorder prints the same strings for plain values). The only behavioural deltas are under secret values, where the old code raised and the new code renders or omits the line. No bar/frame/anchor/colour/size/text change. |
| edit inside the FojjiCore GameTooltip row block | **None.** `git show HEAD:main.lua \| sed -n '1,45p' \| md5sum` equals the working copy (`25c57cc64fd1a581fc8f17399b1406ad`); the first main.lua diff hunk starts at line 245. |

## 3. Operator surface (a) - item tooltip while item data is unloaded

Traced end-to-end; the pin `item tooltip while item data is unloaded` passes.

- `resolveTooltipItem` (main:3884-3912): the link is secrecy-tested before use;
  `GetItemLinkByGUID` is Nilable and is now tested with `type(link) ~= "nil"`
  (main:3903), then secrecy-tested.
- `itemToolTipHook` (main:3914-3999): `IsEquippableItem` pcall + secrecy
  (3942-3945); a single `GetItemInfo` is read via the pcall **ok flag**
  (3962-3966); `itemInfo[2]`/`itemInfo[4]` are nil-gated before the refresh
  request (3967); `ilvl` is secrecy-tested before `> 1` and formatting
  (3971-3974); `gs`/`hs` likewise (3978, 3992-3995).
- `scheduleItemTooltipRefresh` (main:4034-4065): link tested, `IsItemDataCached`
  pcall'd, result secrecy-tested before `== true`.
- `TT_GS:GetItemScoreFromInfo` -> `scoreFromItemInfo` -> `scoreFromItemValues`
  (gearscore:322-400): every value is secrecy-tested before arithmetic or the
  `GS_ItemTypes[ItemEquipLoc]` table key; the "not loaded yet" shape (GetItemInfo
  returns nothing -> all nils) falls through the `and` chain to `return 0`.
- LFI fallback wrapper (LFI:4178-4241): `GetItemInfo` namespace-resolved,
  function-guarded, pcall'd, ok-flag and nil-tested; `IsItemDataCached` returns
  false for an unloaded item without raising.
- Result: an unloaded/nil item cannot reach a comparison or a table key; the
  tooltip line is omitted and the data requested.

## 4. Operator surface (b) - unit-tooltip GearScore row under forced restrictions

Traced end-to-end; pins `unit tooltip while item data is unloaded` and the
GearScore-row pins pass with the throwing `issecretvalue` mock.

- Unit resolution is `safeUnitExists`/`safeUnitIsUnit` based (main:2715-2731,
  1511-1539); every answer is non-secret.
- `guid` is `data.guid` (only when `TT.tooltipDataReadable`) or `safeUnitGUID`,
  then secrecy-tested (main:2825-2826). Under identity restrictions a non-party
  unit's GUID is secret -> `guid = nil` -> the whole score block is skipped
  (`if ((needGsScore or needPawnScore) and guid)`, main:3414) and no row is
  drawn. A party/self unit has a plain GUID and a plain identity, so the item
  wrappers it reads carry no secret identity values.
- `TT_GS:GetScore` (gearscore:466-673): `getPlayerGUID` only accepts a
  `type(arg)=="string"` non-secret argument (269); the self check tests both
  operands before `==` (472-475); `PlayerEnglishClass` comes from
  GetPlayerInfoByGUID (MayReturnNothing, `SecretArguments="AllowedWhenTainted"`,
  no secret returns at the pin or origin/live) and is only `==`-compared;
  item receivers and links are secrecy-tested; every itemID used as a table key
  (`cb_table.items`, `_itemRequestTime`) is a plain number.
- The rendered values (`gearscore`, `avg_ilvl`) are plain numbers produced by
  float math over plain item values; `getGearScoreMemo`/`setGearScoreMemo`
  reject a secret/nil GUID before using it as a memo key (main:1989-2027).
- Result: under forced combat/encounter restrictions the row is either computed
  from plain party/self data or omitted; no secret comparison, index, arithmetic
  or table key is reachable.

## 5. Forever loot-window tooltip - still native

- `itemToolTipHook` returns at its first statement for
  `isForeverLootTooltip(self)` (main:3921-3923), before `clearTooltipVisuals`,
  before any `AddLine`, and before `applyTooltipFonts` / `applyTooltipMaxWidth` /
  `applyTooltipBackdrop` / border writes (4005-4027).
- `onTooltipShow` computes `lootTooltip = isForeverLootTooltip(tooltip)` and
  skips `GetItem` / `resolveTooltipUnit` / `GetDisplayedUnit` entirely for it
  (main:4160-4193).
- No changed hunk is inside `isForeverLootTooltip` (main:2671-2706), the item
  post-call guard, or the loot element ownership checks; no `GameTooltip`
  AddLine/AddDoubleLine override is introduced anywhere.
- Result: no added rows, no re-font, no restyle, no tooltip-data read on the
  loot-window tooltip.

## 6. Contract comparison table (60 independently re-derived sites)

Handling shorthand: **A** argument (token/link) secrecy or literal-token check
before the call, **P** pcall ok flag honoured, **R** return secrecy-tested before
any compare/index/format, **N** nil/Nilable handled without comparing a secret,
**S** MayReturnNothing read as "no value", **K** table-key operand proven plain.

| # | file:line | call | documented contract (mirror) | handling observed |
| --: | :--- | :--- | :--- | :--- |
| 1 | LFI:100-107 | UnitGUID | WOWGUID Nilable; SecretWhenUnitIdentityRestricted; SecretArguments | A P N R |
| 2 | LFI:119-139 | UnitIsUnit | SecretWhenUnitComparisonRestricted; SecretArguments | A P R + C_Secrets pre-check |
| 3 | LFI:160-169 | UnitExists | bool; SecretArguments | A P |
| 4 | LFI:171-180 | UnitIsPlayer | bool; SecretArguments | A P |
| 5 | LFI:182-191 | UnitIsConnected | bool; SecretArguments | A P |
| 6 | LFI:193-202 | UnitIsDeadOrGhost | bool; SecretArguments | A P |
| 7 | LFI:3211-3229 | UnitIsPlayer(arg) | bool; SecretArguments | arg proven non-secret at entry |
| 8 | LFI:3465-3479 | UnitClass | MayReturnNothing; SecretWhenUnitIdentityRestricted | token proven by safeUnitExists; classID R; P |
| 9 | LFI:3489-3498 | UnitSex | Nilable number; SecretWhenUnitIdentityRestricted; SecretArguments | A P R |
| 10 | LFI:4178-4241 | GetItemInfo + ItemLocation shim | MayReturnNothing; SecretArguments | A P S N |
| 11 | LFI:4656-4664 | UnitExists/UnitIsPlayer | bool; SecretArguments | literal tokens |
| 12 | LFI:4935-4966 | UnitExists(insFrame.unit) | bool; SecretArguments | A (safeUnitExists) |
| 13 | LFI:5008-5043 | UnitDistanceSquared | number + bool; SecretArguments | A P R (all comparisons inside pcall) |
| 14 | LFI:5697-5715 | CanInspect | bool; SecretArguments | A P R |
| 15 | LFI:5717-5735 | CheckInteractDistance | bool; SecretArguments | A P R |
| 16 | LFI:5864 | UnitExists/IsConnected/IsDeadOrGhost("player") | bool; SecretArguments | literal token |
| 17 | LFI:5908 | UnitExists("target") | bool; SecretArguments | literal token |
| 18 | LFI:5922-5928 | UnitGroupRolesAssigned | cstring; SecretWhenUnitIdentityRestricted; SecretArguments | generated literal token; A P R before `==` |
| 19 | LFI:5939-5956 | UnitExists("raid"..i / "party"..i) | bool; SecretArguments | generated literal token; P R |
| 20 | LFI:5993-6001 | UnitExists(unitHint) | bool; SecretArguments | A (safeUnitExists) |
| 21 | main:309-316 | UnitGUID | WOWGUID Nilable; SecretWhenUnitIdentityRestricted | A P N R |
| 22 | main:320-396 | safeUnit* boundaries | bool/luaIndex contracts | A P R; UnitInRaid `type(inR)=="number" or inR==true` after R |
| 23 | main:561-563 | UnitClass("player") | MayReturnNothing; player-controlled | literal token; MayReturnNothing -> nil is only compared |
| 24 | main:720-730 | UnitIsOtherPlayersPet | bool; SecretArguments | A P R |
| 25 | main:903-934 | UnitClass (class colour) | MayReturnNothing; SecretWhenUnitIdentityRestricted | gate + P + R before getClassColor key |
| 26 | main:946-988 | UnitCanAttack/UnitIsPlayer/UnitLevel | bool/number; SecretArguments | A added; P; R before `==`/`>`/`+` |
| 27 | main:990-1018 | UnitLevel | number; SecretArguments | A + textLine tested before `==`/gsub |
| 28 | main:1846-1855 | SetPortraitTexture | no returns; SecretArguments | A |
| 29 | main:1904-1918 | UnitPowerMax | number; SecretWhenUnitPowerMaxRestricted; SecretArguments | A; secret result -> bar shown, value uncompared |
| 30 | main:2516-2565 | GetItemInfo(RequestLoadItemDataByID) | MayReturnNothing; SecretArguments | A P S; itemID guarded K |
| 31 | main:2708-2738 | UnitName | SecretWhenUnitNameIdentityRestricted; AllowedWhenTainted | P R |
| 32 | main:2913-2918 | UnitName(unitTarget) | same | R before truthiness/format |
| 33 | main:2936-2949 | UnitClass(target) | MayReturnNothing; SecretWhenUnitIdentityRestricted | P R before class-colour key |
| 34 | main:3020-3027 | UnitClass/UnitRace/UnitLevel | as documented | P R each |
| 35 | main:3131-3158 | UnitIsSameServer | bool; SecretArguments | A P R before `== false` |
| 36 | main:3161-3169 | UnitName(realm) | SecretWhenUnitNameIdentityRestricted | P R before `~= ""` |
| 37 | main:3171-3185 | UnitPVPName | string; SecretWhenUnitIdentityRestricted; SecretArguments | P R before `~= ""`/safeEquals |
| 38 | main:3196-3210 | UnitFactionGroup | cstring; SecretArguments | A P R before `==` |
| 39 | main:3212-3219 | UnitClass(class icon) | as documented | P R before getClassIconMarkup key |
| 40 | main:3221-3228 | UnitGroupRolesAssigned | cstring; SecretWhenUnitIdentityRestricted; SecretArguments | P R before `~=`/ROLE_ICONS key |
| 41 | main:3683-3708 | UnitPowerType/Max/Power | MayReturnNothing / secret number / SecretArguments | A; P; R before PowerBarColor key; type()-nil then bar sink; text only when plain |
| 42 | main:3884-3912 | GetItemLinkByGUID | string Nilable; SecretArguments | A P N R |
| 43 | main:3914-3999 | item path | GetItemInfo/IsEquippableItem/UnitClass contracts | A P S R; `cls` R before `== "HUNTER"` |
| 44 | main:4034-4065 | GetItemInfoInstant(RequestLoadItemDataByID) | MayReturnNothing; SecretArguments | A P S K |
| 45 | main:5171-5358 | /tt diag reads | the Unit*/Item contracts above | literals; R before compare/format; link A P |
| 46 | main:5917-5924 | UnitName("player") | SecretWhenUnitNameIdentityRestricted | literal token; R before `~= ""` |
| 47 | main:6095-6127 | GetInventoryItemLink/GetItemInfo | undocumented legacy / MayReturnNothing | A (link) P R (rarity) |
| 48 | options:47-56,5001,5085,5134 | UnitGUID("player") via TT.safeUnitGUID | WOWGUID Nilable; SecretWhenUnitIdentityRestricted | delegates to boundary helper; nil -> no highlight |
| 49 | options:4304-4305,4770-4771 | SetPortraitTexture("player") | SecretArguments; literal token | pcall + presence guard |
| 50 | gearscore:241-261 | UnitIsUnit | SecretWhenUnitComparisonRestricted; SecretArguments | A P R + C_Secrets pre-check |
| 51 | gearscore:263-280 | GUIDIsPlayer/UnitIsPlayer/UnitGUID | SecretArguments / bool / Nilable GUID | A before each; P; R; truthiness on string (O3) |
| 52 | gearscore:466-480 | UnitGUID("player") | WOWGUID Nilable | literal token; P R before `==` |
| 53 | gearscore:484 | GetPlayerInfoByGUID | MayReturnNothing; AllowedWhenTainted; no secret returns | P S; result only `==`-compared |
| 54 | gearscore:522-580 | Item:IsItemDataCached/GetItemID/GetItemLink | C_Item contracts (SecretArguments) | receiver guard; itemID guarded before dedupe key/request |
| 55 | gearscore:588-597 | GetItemInfo(links) | MayReturnNothing; SecretArguments | links R before the call |
| 56 | gearscore:609-658 | slot loop Item methods | C_Item contracts | receiver guard; link/itemID R before compare/insert |
| 57 | pawn:100-146 | UnitIsUnit/UnitIsPlayer/UnitGUID/GUIDIsPlayer | as documented | A P R (truthiness on string, O3) |
| 58 | pawn:200-213 | UnitGUID("player") | WOWGUID Nilable | literal token; P R before `==` |
| 59 | pawn:246-282 | Item:IsItemDataCached/GetItemLink/GetItemID | C_Item contracts | receiver guard; link R before scoring; itemID R |
| 60 | pawn:29,281-282 | RequestLoadItemDataByID | SecretArguments; no returns | nil-guarded, pcall, plain itemID |

## 7. Red/green evidence (re-run by the reviewer)

```
lua5.1 Tests/harness/contract_pins_test.lua        -> CONTRACT pins: 62/62 passed
luajit Tests/harness/contract_pins_test.lua        -> CONTRACT pins: 62/62 passed
TACOTIP_MAIN_OVERRIDE=/tmp/head_main.lua lua5.1 .../contract_pins_test.lua
                                                   -> 59/62 (3 FAIL: UnitPowerMax arg,
                                                      UnitCanAttack/IsPlayer/Level arg,
                                                      WarmGearItemData secret link)
TACOTIP_LIB_OVERRIDE=/tmp/head_lfi.lua lua5.1 .../contract_pins_test.lua
                                                   -> 54/62 (8 FAIL: wrapper x3,
                                                      gearscore row x2, PlayerGUIDToUnitToken x3)
bash Tests/harness/run_all.sh                      -> TOTAL 75 invocations: 75 passed
luac5.1 -p main.lua options.lua gearscore.lua pawn.lua LFI.lua -> OK
luacheck .                                         -> 0 warnings / 0 errors in 91 files
```

Full diff read: 37 hunks / +146-41 across the five files. The 25 functional
audit hunks are the ones listed in t9/t10/t11; the remaining 12 are comments,
`---@secret-guard`/`---@return` annotations, `inject-field` suppression removal
and line-wrap formatting that were in the tree before the team started (verified
by mtimes and by `AGENTS.md`/`workshop.md` describing that LSP pass), with no
runtime effect.

## 8. Residual observations (non-blocking; no counterexample, no required fix)

- **O1 - main.lua:5340.** The second `fnUnitClass(activeUnit)` call in the `/tt diag`
  path is not itself followed by an `isSecretValue` test, while the first one at
  :5199 is. `classToken` then flows into `CI:GetSpecializationName`, which uses
  it as a table key (`CLASS_IDS[class]`, `lib.spec_table[class]`). t10's
  justification ("classFilename plain") is imprecise: `UnitClass` carries a
  function-level `SecretWhenUnitIdentityRestricted`
  (`SecretPredicatesDocumentation.lua:141-146`), so its returns are secret on a
  restricted unit; the separate `ConditionalSecret` on `className` is
  per-return. The site is nevertheless not a counterexample because the branch
  also needs a non-nil `specIndex` from `CI:GetSpecialization(guid)`, and a
  secret `classFilename` implies a secret GUID from the same predicate
  (`guid = "<secret>"` -> `specIndex = nil` -> the call is skipped). If the
  branch is ever refactored, add `not isSecretValue(classToken)` before the
  lookup.
- **O2 - LFI:4186.** The fallback ItemLocation shim computes
  `tonumber(string.match(link, "item:(%d+)"))` eagerly, before the
  `isSecretValue(link)` guard that t9 added inside `IsItemDataCached`; a secret
  link would raise at wrapper creation. It is unreachable today because
  `Item.CreateFromItemLink` is Blizzard Lua present on all five branches
  (`Blizzard_ObjectAPI/[Family]/Item.lua`; the toc's `[Family]` resolves to the
  Mainline family, which Camelot uses), and no documented item API carries a
  `SecretWhen*`/`SecretReturns` annotation. The fix is still worth mirroring at
  the top of `createItemWrapper` if the fallback ever becomes reachable.
- **O3 - gearscore:274, pawn:212, main:5192-5198.** Nilable `UnitGUID`/tooltip-text
  returns are truthiness-tested before the `isSecretValue` test rather than with
  `type(v) == "nil"`. For documented `WOWGUID`/`cstring` values truthiness is
  legal (only secret *booleans* fail a boolean test), so this cannot raise; it is
  a consistency gap with the rule applied in main.lua and LFI, not a defect.
- **O4 - LFI:3224, LFI:4591.** Two pre-existing `---@diagnostic disable`
  directives remain; both exist at HEAD, and the review confirms **none was
  added** by t9-t11 (`git diff -U0 -- '*.lua' | grep '^+' | grep diagnostic` is
  empty). If the release gate bans all directives, that is a gate-policy
  decision for t14, not a contract regression.
- **O5 - t13 pin mock shape.** The "secret Item receiver" pin models a secret
  wrapper table, while on Forever `GetInventoryItemMixin` returns Blizzard's
  plain `ItemMixin` object; the carrier that could be secret in that model is
  the link stored inside it. No documented item API produces a secret link, so
  this does not invalidate the pin; it is a fidelity note for future hardening
  (a pcall around the `Item` method calls in gearscore/pawn would cover it).
- **O6 - pre-existing, outside the Unit*/Item* scope.** `main.lua:3046-3057`
  calls `string.match(text[i], ...)` on tooltip line text after only a
  truthiness test (the `isForever` row-clearing at :2906-2910 and the player
  early-returns at :2882-2883 narrow this, but Retail does not clear the tail
  rows). Not part of this audit's call-site set and unchanged by it; recorded so
  the next secret-hygiene pass can pick it up.

## 9. Verdict

**PASS.** No counterexample found: every functional change in t9-t11 is correct
against the mirror contract, every changed hunk was read, all 60 independently
re-derived call contracts match the observed handling, both operator surfaces
are proven, the FojjiCore block and the Forever loot-window tooltip are
untouched, no diagnostic suppression was introduced, and the pins are red on the
HEAD copies and green on the tree (62/62, full suite 75/75, luacheck 0/0,
`luac5.1 -p` clean). The residual observations above are unreachable or
pre-existing and require no change to ship this contract audit.
