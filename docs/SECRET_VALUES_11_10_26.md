# WoW Forever (Camelot / Interface 16001) Secret Values & Add-On Restriction Reference

**Document Date**: November 10, 2026
**Target environment**: WoW Forever — the **Camelot** client, interface `16001`. `WOW_PROJECT_ID` is `MAINLINE` (1), exactly like Retail, but this client is **not** mainline: its UI lives in the `Camelot/` folders (`Interface/AddOns/Blizzard_PlayerSpells/Camelot/ClassTalents/…`, `Interface/AddOns/Blizzard_InspectUI/Camelot/…`), and a Blizzard TOC `[Game]` token resolves to Camelot.
**Client truth**: `/home/sam/wow-ui-source`, read-only, `origin/`-qualified. Only `origin/forever` was read for this document. Nothing here comes from `origin/live`, `origin/beta`, or any classic branch.
**Pinned build**: `1.60.1.70888` (`git show origin/forever:version.txt`), branch tip `4cd0ab752`. **This pin is a snapshot.** Every `file:line` below was read at that build; a later build can move any line, so re-read the cited entry before quoting it again.
**Add-on scope**: TacoTip Core (`main.lua`, `gearscore.lua`, `pawn.lua`, `options.lua`, `Libs/LibForeverInspector/LibForeverInspector.lua`) and TacoTip Extras (`Core.lua`, `RankBrowser.lua`, `Scanner.lua`).

---

## 1. Executive summary — three independent mechanisms, not "instance combat"

The previous revision of this document framed everything as *"inside instances, combat triggers a restriction subsystem"*. That framing is wrong in three separate ways, and each way caused a real defect in the add-on, so it is replaced here.

### 1.1 There are six restriction types, and they are independent

`Enum.AddOnRestrictionType` (`Interface/AddOns/Blizzard_APIDocumentationGenerated/RestrictedActionsConstantsDocumentation.lua:19-33`) declares six types, each with its own life cycle:

| Enum value | Name | Client documentation (verbatim) |
| :--- | :--- | :--- |
| 0 | `Combat` | "The player is actively affecting combat." (`:26`) |
| 1 | `Encounter` | "The player is actively participating in an instance encounter." (`:27`) |
| 2 | `ChallengeMode` | "The player is in an active and incomplete challenge mode or mythic keystone dungeon." (`:28`) |
| 3 | `PvPMatch` | "The player is in an active and incomplete PvP match." (`:29`) |
| 4 | `Map` | "The player is on a map that applies addon restrictions." (`:30`) |
| 5 | `Chat` | "The player is in a state where addon chat communications are restricted." (`:31`) |

**Encounter is not Combat.** They are separate types with separate definitions (`:26`, `:27`), each with its own state, so one can be active while the other is not — a pull and an instance encounter do not produce the same restriction set. A dungeon can also be `Map`-restricted while out of combat entirely, and a PvP match sets `PvPMatch` even when no combat is in progress. "We are in a dungeon" therefore tells an add-on almost nothing about which secret predicates are currently firing; ask the type you care about.

### 1.2 There are three different predicate scopes

Which predicate an API entry carries is what decides when its return is secret. The predicates fall into three scopes, and the scope is visible in the predicate's own documentation (`SecretPredicatesDocumentation.lua`):

- **Restriction-scoped** — fires while one of the restriction types above is active. `SecretWhenInCombat` is Combat only ("when combat addon restrictions are in effect", `:95-97`); `SecretWhenAurasRestricted`, `SecretWhenCooldownsRestricted`, `SecretWhenUnitAuraRestricted` and `SecretWhenTotemSlotSecret` cover combat/encounter/challenge-mode/PvP (`:80-82`, `:85-87`, `:90-92`, `:110-112`); `SecretInActivePvPMatch` is PvP-only (`:60-62`).
- **Map-scoped** — fires because the player is standing on a restricted map, combat or not. `SecretOnRestrictedMaps`: "when the player is on an addon-restricted map such as a dungeon or raid" (`:70-72`). `SecretInChatMessagingLockdown` fires on encounter/challenge/PvP *or* a communication-restricted map (`:65-67`). `SecretWhenUnitComparisonRestricted` is explicitly map-scoped: "This restriction only applies when the player is on an addon-restricted map" (`:120-122`).
- **Unit-scoped** — fires because of *which unit* is being asked, not the encounter phase. `SecretWhenUnitIdentityRestricted`: "when the unit isn't player-controlled or in the party/raid" (`:130-132`); `SecretWhenUnitHealthMaxRestricted`: "when the unit isn't player-controlled" (`:125-127`); `SecretWhenUnitPowerMaxRestricted` and `SecretWhenUnitPowerRestricted` likewise (`:145-152`); `SecretWhenUnitNameIdentityRestricted` (`:135-137`); `SecretWhenUnitStatsRestricted` (`:155-157`); `SecretWhenUnitThreatStateRestricted` / `…ValuesRestricted` (`:160-167`); `SecretWhenUnitSpellCastRestricted` ("if the unit being queried for cast information is not the player or their pet", `:115-117`).

A tooltip that asks about a **boss unit** carries unit-scoped secrecy even in the open world; a tooltip that asks about **yourself** stays readable even during a boss fight. Both directions are load-bearing for TacoTip.

### 1.3 What the add-on must actually do about it

1. **Never boolean-test a value that a `SecretWhen*`-guarded API returned** — not `if v then`, not `not v`, not `v == true`, not `v ~= false`, not `v == nil`.
2. **Never pass a secret value into an API annotated `SecretArguments = "AllowedWhenUntainted"`** from tainted add-on code — the engine refuses it, and the refusal surfaces as a Lua error (see §4).
3. **Assume neither**: detect. The secret API itself (`issecretvalue` / `canaccessvalue`) is also `AllowedWhenUntainted`, so the *predicate call* can throw, and a throw must be read as "secret" (see §4).
4. **Degrade to unknown, never to a guess.** A refused read produces "no data" for that row, not a default that reads as real data.

---

## 2. The mechanism: `C_RestrictedActions`, `ADDON_RESTRICTION_STATE_CHANGED`, `C_Secrets`

### 2.1 State and state changes — `C_RestrictedActions`

`Interface/AddOns/Blizzard_APIDocumentationGenerated/RestrictedActionsDocumentation.lua` declares the namespace (`Namespace = "C_RestrictedActions"` at `:5`):

- **`C_RestrictedActions.GetAddOnRestrictionState(type)`** (`:29-43`; doc string `:32`) — "Returns the current state of an addon restriction type." Returns `Enum.AddOnRestrictionState` (see below).
- **`C_RestrictedActions.IsAddOnRestrictionActive(type)`** (`:55-69`; doc string `:58`) — "Returns true if an addon restriction type is in an active state. **Will always return false during dispatch of `ADDON_RESTRICTION_STATE_CHANGED`.**" This is the per-moment gate an add-on should read.
- **`C_RestrictedActions.CheckAllowProtectedFunctions(object, silent)`** (`:11-27`) — protected-function permission, a different question from secrecy.

`Enum.AddOnRestrictionState` (`RestrictedActionsConstantsDocumentation.lua:6-16`) has three values: `Inactive` = 0, `Activating` = 1 ("during the dispatch of `ADDON_RESTRICTION_STATE_CHANGED` … won't be enforced until event dispatch has completed"), `Active` = 2. The `Activating` state exists precisely so an add-on can prepare before enforcement starts.

**`ADDON_RESTRICTION_STATE_CHANGED`** (`RestrictedActionsDocumentation.lua:97-107`; `LiteralName` `:99`, sequencing doc `:101`, payload `:104-105`): payload `(type, state)`, and "This event is sequenced such that it will always be fired before a restriction becomes active, or after it is deactivated."

The client uses exactly this mechanism itself: `Blizzard_GamepadSmartNavigation/SecureHelper.lua:14-15` binds `C_RestrictedActions.IsAddOnRestrictionActive` and `Enum.AddOnRestrictionType.Combat`, and `:27` gates a secure-or-out-of-combat test on it; `SmartNavigation.lua:1512` refuses a tainted navigation override while that restriction is active. **This is the real mechanism.** There is no "instance combat flag" API and no boolean on the add-on side that stands in for it.

### 2.2 `C_Secrets` — a build capability, not a state

`Interface/AddOns/Blizzard_APIDocumentationGenerated/SecretPredicateAPIDocumentation.lua` declares `Name = "SecretUtil"` (`:3`), `Namespace = "C_Secrets"` (`:5`). It is a namespace of **questions**, and two of them are commonly confused:

- **`C_Secrets.HasSecretRestrictions()`** (`:93-99`; doc string `:95`) — "Returns true if this client build has secret value restrictions enabled. **If false, all APIs that are tagged as potentially returning secrets will never do so.**" This is a *build-capability probe*: it is a property of the client build, not of the moment; it is **not** a per-moment state and must never be used as "can I read this unit right now". The per-moment question is `IsAddOnRestrictionActive(type)` (§2.1), and the per-API question is the predicate named on the API entry (§2.3).
  The client uses it the same way — as a capability switch around a whole code path: `Blizzard_UnitFrame/Shared/UnitFrameUtil.lua:377-379` (`ShouldArenaOpponentSpecBeSecret` returns `C_Secrets.HasSecretRestrictions()`) then secret-wraps an entire display-info table only when it is true (`:387-391`).
- **`C_Secrets.CanCompareUnitTokens(unit1, unit2)`** (`:12-26`; doc string `:15`) — "Returns true if queries to compare two input unit tokens are permitted. If this returns false, APIs guarded by the `RequiresComparableUnitTokens` predicate will fail." Its arguments are `UnitToken` and its return is a plain `bool`, so it is the sanctioned way to ask *before* calling `UnitIsUnit` (§5). `SecretArguments = "AllowedWhenUntainted"` (`:14`), so it can itself refuse a secret token — which the add-on's guard must also treat as a refusal.

### 2.3 The predicate catalogue (real names only)

`SecretPredicatesDocumentation.lua` is the authority for the names below; each entry is a predicate an API can carry. The ones that matter for a tooltip add-on:

| Predicate | Scope | What fires it (client documentation) |
| :--- | :--- | :--- |
| `RequiresComparableUnitTokens` | precondition | Token pairs must be comparable; guarded APIs "fail" when `CanCompareUnitTokens` is false (`:10-13`; `FailureMode = "ReturnNothing"` at `:12`). |
| `SecretWhenUnitIdentityRestricted` | unit | Unit is not player-controlled or in the party/raid (`:130-132`). |
| `SecretWhenUnitNameIdentityRestricted` | unit | Unit identity rules, except a player in PvP (`:135-137`). |
| `SecretWhenUnitHealthMaxRestricted` | unit | Unit is not player-controlled (`:125-127`). |
| `SecretWhenUnitPowerRestricted` | unit | Power types not flagged never-secret (`:150-152`). |
| `SecretWhenUnitPowerMaxRestricted` | unit | Unit is not player-controlled (`:145-147`). |
| `SecretWhenUnitComparisonRestricted` | unit + map | Comparisons of compound tokens are always secret; otherwise only on addon-restricted maps (`:120-122`). |
| `SecretWhenUnitStatsRestricted` | unit | Unit stats generally (`:155-157`). |
| `SecretWhenUnitAuraRestricted` / `SecretWhenAurasRestricted` | restriction | Combat/encounter/challenge/PvP (`:80-82`, `:85-87`). |
| `SecretWhenCooldownsRestricted` | restriction | Same set (`:90-92`). |
| `SecretWhenInCombat` | restriction | Combat only (`:95-97`). |
| `SecretInActivePvPMatch` | restriction | PvP match (`:60-62`). |
| `SecretInChatMessagingLockdown` | map + restriction | Encounter/challenge/PvP, or a communication-restricted map (`:65-67`). |
| `SecretOnRestrictedMaps` | map | The player is on an addon-restricted map (`:70-72`). |
| `SecretWhenAnchoringSecret` | object | The object carries secret anchoring info (`:75-77`). |
| `SecretWhenLossOfControlRestricted` / `…InfoRestricted` | always | Always secret, except an active PvP spectator/commentator (`:100-107`). |

Two facts about this catalogue that the previous revision got wrong:

- **`SecretOnRestrictedMaps` is defined but carried by zero APIs at this pin.** Grepping the whole generated-documentation directory finds exactly one occurrence — the definition itself (`SecretPredicatesDocumentation.lua:70`). Do not cite it as the reason a specific API went secret; cite the predicate the API actually carries.
- **`SecretArguments` is a property of the *call*, not a predicate inside it.** Its three values on this pin are `"AllowedWhenUntainted"` (3,684 entries), `"AllowedWhenTainted"` (176) and `"NotAllowed"` (92); `"NotAllowed"` refuses a secret argument even from untainted code. See §4. The per-return properties are the `SecretWhen*` keys, `SecretReturns = true`, `SecretInChatMessagingLockdown`, and per-field `ConditionalSecret = true` (e.g. `UnitClass`'s `className`, `UnitDocumentation.lua:924`).

### 2.4 Names that do not exist — do not reintroduce them

The previous revision of this file invented engine keys by dropping the `SecretWhen` prefix and normalizing the names. **None of the following exist on `origin/forever`** (verified by grepping `Interface/AddOns/Blizzard_APIDocumentationGenerated/`):

`UnitIdentityRestricted`, `UnitPowerMaxRestricted`, `UnitNameIdentityRestricted`, `UnitComparisonRestricted`, `UnitPowerRestricted`, `UnitHealthMaxRestricted`, `UnitHealthRestricted`, `InstanceRestricted`, `CombatRestricted`. They are spelled out here for one reason only — so that a search for the wrong name lands on this warning — and must not be quoted as engine keys anywhere.

The real names are the `SecretWhen*` keys in §2.3. If a claim in a bug report or a comment uses the short form, translate it to the real key before acting on it.

---

## 3. API catalogue — annotations exactly as the client declares them

Each entry gives the generated-documentation file and the line where the entry begins, then the annotations **verbatim**. Where an argument or return shape matters to the add-on, it is called out in the rule line; the full shape is not re-typed here, because a hand-copied signature is exactly the kind of claim that drifts between builds — read the cited entry.

### 3.1 The secret predicates themselves

#### `issecretvalue`
- **Documentation**: `FrameScriptDocumentation.lua:287` (entry); `SecretArguments = "AllowedWhenUntainted"` at `:290`; `SecureHooksAllowed = false` at `:289`.
- **Documentation string**: "Returns true if a supplied value is a secret value." (`:291`)
- **Rule**: **the predicate call itself can throw** from tainted code. Never call it bare. See §4.

#### `canaccessvalue`
- **Documentation**: `FrameScriptDocumentation.lua:65` (entry); `SecretArguments = "AllowedWhenUntainted"` at `:68`.
- **Documentation string**: "Returns true if the immediate calling function has appropriate permissions to access and operate on a specific value." (`:69`)
- **Rule**: same trap as `issecretvalue`; the add-on reads it through `rawget(_G, "canaccessvalue")` so that a client without it is not an error.

### 3.2 Existence, identity and tokens

| API | Entry | Annotations (verbatim), plus shape where the add-on depends on it |
| :--- | :--- | :--- |
| `UnitExists` | `UnitDocumentation.lua:1192` | `SecretArguments = "AllowedWhenUntainted"` |
| `UnitIsPlayer` | `UnitDocumentation.lua:2271` | `SecretArguments = "AllowedWhenUntainted"` |
| `UnitIsUnit` | `UnitDocumentation.lua:2410` | `RequiresComparableUnitTokens = true`; `SecretWhenUnitComparisonRestricted = true`; `SecretArguments = "AllowedWhenUntainted"` |
| `UnitTokenFromGUID` | `UnitDocumentation.lua:3296` | `SecretWhenUnitIdentityRestricted = true`; `SecretArguments = "AllowedWhenTainted"` |
| `UnitGUID` | `UnitDocumentation.lua:1241` | `SecretWhenUnitIdentityRestricted = true`; `SecretArguments = "AllowedWhenUntainted"` |
| `UnitName` | `UnitDocumentation.lua:2489` | `SecretWhenUnitNameIdentityRestricted = true`; `SecretArguments = "AllowedWhenTainted"` |
| `UnitPVPName` | `UnitDocumentation.lua:2601` | `SecretWhenUnitIdentityRestricted = true`; `SecretArguments = "AllowedWhenUntainted"` |
| `UnitClass` | `UnitDocumentation.lua:911` | `MayReturnNothing = true`; `SecretWhenUnitIdentityRestricted = true`; `SecretArguments = "AllowedWhenUntainted"`; `className` return is `ConditionalSecret = true` (`:924`) |
| `UnitRace` | `UnitDocumentation.lua:2925` | `MayReturnNothing = true`; `SecretWhenUnitIdentityRestricted = true`; `SecretArguments = "AllowedWhenUntainted"` |
| `UnitSex` | `UnitDocumentation.lua:3069` | `SecretWhenUnitIdentityRestricted = true`; `SecretArguments = "AllowedWhenUntainted"` |
| `UnitLevel` | `UnitDocumentation.lua:2474` | `SecretArguments = "AllowedWhenUntainted"` |
| `UnitClassification` | `UnitDocumentation.lua:966` | `SecretArguments = "AllowedWhenUntainted"` |
| `UnitFactionGroup` | `UnitDocumentation.lua:1207` | `SecretArguments = "AllowedWhenUntainted"` |
| `UnitReaction` | `UnitDocumentation.lua:2983` | `SecretArguments = "AllowedWhenUntainted"` |

**Rules.** `UnitIsUnit` is the one API here whose *boolean answer* can itself be secret — see §5, and never boolean-test it. `UnitGUID` / `UnitClass` / `UnitRace` / `UnitPVPName` returns can be secret strings, so they may be compared only after a secret test and may never be used as table keys. `UnitName` is `AllowedWhenTainted`, i.e. tainted code may *pass* a secret name, but what comes back is still secret under the name-identity predicate — "allowed to pass" is not "clear to read". `UnitTokenFromGUID` is also `AllowedWhenTainted` and its return carries the identity predicate.

### 3.3 Group, relationship and role

| API | Entry | Annotations (verbatim), plus shape where the add-on depends on it |
| :--- | :--- | :--- |
| `UnitInParty` | `UnitDocumentation.lua:1637` | `SecretArguments = "AllowedWhenUntainted"` — **no** secret predicate on the return |
| `UnitInRaid` | `UnitDocumentation.lua:1683` | `SecretWhenUnitIdentityRestricted = true`; `SecretArguments = "AllowedWhenUntainted"` |
| `UnitIsEnemy` | `UnitDocumentation.lua:1946` | `SecretArguments = "AllowedWhenUntainted"` |
| `UnitIsFriend` | `UnitDocumentation.lua:1977` | `SecretArguments = "AllowedWhenUntainted"` |
| `UnitCanAttack` | `UnitDocumentation.lua:763` | `SecretArguments = "AllowedWhenUntainted"` |
| `UnitIsSameServer` | `PlayerLocationDocumentation.lua:104` | `SecretArguments = "AllowedWhenUntainted"` |
| `UnitGroupRolesAssigned` | `UnitDocumentation.lua:1318` | `SecretWhenUnitIdentityRestricted = true`; `SecretArguments = "AllowedWhenUntainted"` |
| `UnitIsOtherPlayersPet` | `UnitDocumentation.lua:2193` | `SecretArguments = "AllowedWhenUntainted"` |
| `UnitIsPVP` | `UnitDocumentation.lua:2225` | `SecretWhenUnitIdentityRestricted = true`; `SecretArguments = "AllowedWhenUntainted"` |
| `UnitIsAFK` | `UnitDocumentation.lua:1778` | `SecretInChatMessagingLockdown = true`; `SecretArguments = "AllowedWhenUntainted"` |
| `UnitIsDND` | `UnitDocumentation.lua:1900` | `SecretInChatMessagingLockdown = true`; `SecretArguments = "AllowedWhenUntainted"` |

**Rules.** `UnitInRaid` returns a `luaIndex` and it can be secret — `main.lua:2903` therefore calls `safeUnitInRaid`, never the bare global. `UnitInParty` carries no secret predicate at this pin, but the add-on still routes it through `safeUnitInParty` (`main.lua:2520`), because the *argument* can be a secret token and `SecretArguments` refuses that. `UnitIsPVP` and `UnitGroupRolesAssigned` are secret for a boss or a nameplate unit — both are read behind the guarded helpers before any comparison.

### 3.4 Vitals, status, power

| API | Entry | Annotations (verbatim), plus shape where the add-on depends on it |
| :--- | :--- | :--- |
| `UnitHealth` | `UnitDocumentation.lua:1526` | `SecretReturns = true`; `SecretArguments = "AllowedWhenUntainted"` |
| `UnitHealthMax` | `UnitDocumentation.lua:1472` | `SecretWhenUnitHealthMaxRestricted = true`; `SecretArguments = "AllowedWhenUntainted"` |
| `UnitPower` | `UnitDocumentation.lua:2732` | `SecretWhenUnitPowerRestricted = true`; `SecretArguments = "AllowedWhenUntainted"` |
| `UnitPowerMax` | `UnitDocumentation.lua:2801` | `SecretWhenUnitPowerMaxRestricted = true`; `SecretArguments = "AllowedWhenUntainted"` |
| `UnitPowerType` | `UnitDocumentation.lua:2859` | `MayReturnNothing = true`; `SecretArguments = "AllowedWhenUntainted"` |
| `UnitIsDead` | `UnitDocumentation.lua:1916` | `SecretArguments = "AllowedWhenUntainted"` |
| `UnitIsGhost` | `UnitDocumentation.lua:2008` | `SecretArguments = "AllowedWhenUntainted"` |
| `UnitIsFeignDeath` | `UnitDocumentation.lua:1962` | `SecretArguments = "AllowedWhenUntainted"` |
| `UnitIsConnected` | `UnitDocumentation.lua:1855` | `SecretArguments = "AllowedWhenUntainted"` |
| `UnitIsVisible` | `UnitDocumentation.lua:2428` | `SecretArguments = "AllowedWhenUntainted"` |
| `UnitDistanceSquared` | `UnitDocumentation.lua:1108` | `SecretArguments = "AllowedWhenUntainted"` |

**Rules.** Status bars accept secret numbers directly — `SetMinMaxValues` (`SimpleStatusBarAPIDocumentation.lua:229`, `SecretArgumentsAddAspect = { Enum.SecretAspect.BarValue }` at `:231`, `SecretArguments = "AllowedWhenTainted"` at `:232`) and `SetValue` (`:355`, same pair at `:357-358`) — so the power and health bars pass `UnitPower` / `UnitPowerMax` / `UnitHealth` / `UnitHealthMax` through untouched. **Any Lua comparison on those numbers throws** — the show gate must therefore treat "secret" as "show" rather than computing `max > 0`. `UnitDistanceSquared` returns are not annotated as secret at this pin, but the add-on still guards the read: the *argument* can be a secret token, and a diagnostic that throws is worse than a diagnostic that says "unknown".

### 3.5 Inspection and distance

| API | Entry | Annotations (verbatim), plus shape where the add-on depends on it |
| :--- | :--- | :--- |
| `CanInspect` | `PlayerScriptDocumentation.lua:55` | `SecretArguments = "AllowedWhenUntainted"`; one argument (`targetGUID`, typed `UnitToken`), one `bool` return |
| `CheckInteractDistance` | `PlayerScriptDocumentation.lua:114` | `SecretArguments = "AllowedWhenUntainted"` |
| `NotifyInspect` | `PlayerScriptDocumentation.lua:1516` | `SecretArguments = "AllowedWhenUntainted"`; one argument (`targetGUID`, typed `UnitToken`); **no** returns |

**Rules.** These are the calls that drive the inspect queue, and all three refuse a secret argument. `CanInspect` is called with exactly one argument in TacoTip (an operator invariant). On Forever/Retail either signal is enough, the query first (`Libs/LibForeverInspector/LibForeverInspector.lua:4698-4726`); on the classic family the distance signal is consulted first and the query only if it passes (`:4729-4733`). `NotifyInspect` has no return value, so a `pcall` result is the only signal that it was refused — that is the "inspect range" learning path.

### 3.6 Map and zone

| API | Entry | Annotations (verbatim), plus shape where the add-on depends on it |
| :--- | :--- | :--- |
| `GetBestMapForUnit` | `MapDocumentation.lua:49` | `SecretArguments = "AllowedWhenUntainted"`; `Documentation = { "Only works for the player and party members." }` (`:52`) |
| `GetMapInfo` | `MapDocumentation.lua:312` | `MayReturnNothing = true`; `SecretArguments = "AllowedWhenUntainted"` |

**Rules.** The documented scope is *player and party members*, so the Forever zone row is drawn only where the client answers and never guessed. A `mouseover` or `target` token frequently gets no answer; the row asks the owner frame's own token instead. Both calls are `pcall`'d and the map name is secret-tested before it is concatenated into a line.

### 3.7 Specialization and Camelot traits

| API | Entry | Annotations (verbatim), plus shape where the add-on depends on it |
| :--- | :--- | :--- |
| `C_SpecializationInfo.GetSpecialization` | `SpecializationInfoDocumentation.lua:237` | `SecretArguments = "AllowedWhenUntainted"` |
| `C_SpecializationInfo.GetSpecializationInfo` | `SpecializationInfoDocumentation.lua:254` | `SecretArguments = "AllowedWhenUntainted"` |
| `C_Traits.GetConfigInfo` | `SharedTraitsDocumentation.lua:201` | `MayReturnNothing = true`; `SecretArguments = "AllowedWhenUntainted"` |
| `C_Traits.GetGroupCurrencyInfo` | `SharedTraitsDocumentation.lua:281` | `SecretArguments = "AllowedWhenUntainted"` |
| `C_Traits.GetGroupDisplayInfoByTreeID` | `SharedTraitsDocumentation.lua:297` | `SecretArguments = "AllowedWhenUntainted"` |
| `C_Traits.HasValidInspectData` | `SharedTraitsDocumentation.lua:603` | **no annotations, and no `Documentation` string** |

**On `C_Traits.HasValidInspectData` — a qualified claim, not a quoted contract.** The generated entry declares only the return `hasValidInspectData` (`:603-610`); there is no doc string that says what it means. What actually supports the add-on's reading is Blizzard's own use of it as the *inspect-talent availability gate*: the inspect paperdoll enables its Talents button with `C_Traits.HasValidInspectData()` (`Blizzard_InspectUI/Mainline/InspectPaperDollFrame.lua:69,71`), opens the class-talents tab only when it answers true (`:287`), and greys the button with `UNAVAILABLE` when it does not (`:296-302`). "True means the client has the inspected player's trait data" is therefore an **inference from client usage**, not a documented guarantee — which is why the add-on only reads it under `pcall` and treats "no data" as "draw no line".

### 3.8 Tooltip and loot data

| API | Entry | Annotations (verbatim), plus shape where the add-on depends on it |
| :--- | :--- | :--- |
| `C_TooltipInfo.GetLootItem` | `TooltipInfoDocumentation.lua:554` | `MayReturnNothing = true`; `SecretArguments = "AllowedWhenUntainted"` |
| `C_TooltipInfo.GetLootRollItem` | `TooltipInfoDocumentation.lua:570` | `MayReturnNothing = true`; `SecretArguments = "AllowedWhenUntainted"` |
| `C_TooltipInfo.GetHyperlink` | `TooltipInfoDocumentation.lua:337` | `MayReturnNothing = true`; `SecretArguments = "AllowedWhenUntainted"` |
| `C_TooltipInfo.GetUnit` | `TooltipInfoDocumentation.lua:1181` | `MayReturnNothing = true`; `SecretArguments = "AllowedWhenUntainted"` |

**Rules.** These are getters behind secure delegates (§6). The add-on must not call them for a loot-window tooltip and must not hook the delegate that does.

### 3.9 Items and equipment

| API | Entry | Annotations (verbatim), plus shape where the add-on depends on it |
| :--- | :--- | :--- |
| `IsEquippableItem` | `ItemDocumentation.lua:1324` | `SecretArguments = "AllowedWhenUntainted"` |
| `C_Item.GetItemInfo` (`GetItemInfo`) | `ItemDocumentation.lua:626` | `MayReturnNothing = true`; `SecretArguments = "AllowedWhenUntainted"` |
| `C_Item.GetItemInfoInstant` | `ItemDocumentation.lua:659` | `MayReturnNothing = true`; `SecretArguments = "AllowedWhenUntainted"` |
| `C_Item.GetItemLinkByGUID` | `ItemDocumentation.lua:771` | `SecretArguments = "AllowedWhenUntainted"` |
| `C_Item.RequestLoadItemDataByID` | `ItemDocumentation.lua:1710` | `SecretArguments = "AllowedWhenUntainted"` |
| `GetInventoryItemLink` | **not in the generated documentation at this pin** | no annotations available; the global is used by client Lua (`Blizzard_ChatFrameBase/Shared/ChatFrameUtil.lua:1223`, `Blizzard_InspectUI/Mainline/InspectPaperDollFrame.lua:220`) |

**Rules.** Item reads are `pcall`'d and the returned name/link is secret-tested before it is stored, because a secret string must never become a cache key or a comparison operand. `GetInventoryItemLink` has no generated entry on this pin, so no annotation may be quoted for it — the add-on's rule is the conservative one: `pcall` plus a secret test on the returned link, because the *unit* argument can be secret and the link can be too.

---

## 4. The strong guard rule — and why a throw means "secret"

### 4.1 The annotation that creates the trap

`issecretvalue` and `canaccessvalue` are declared `SecretArguments = "AllowedWhenUntainted"` (`FrameScriptDocumentation.lua:287-291` and `:65-69`). The annotation means: a *secret* argument is acceptable only from untainted execution. Add-on code is tainted, so when the value being tested **is** secret, the predicate call is refused.

Blizzard states the resulting behaviour itself, in the tooltip data handler that faces the same problem:

> "The calling function doesn't have access to secret values. This is expected to occur for tainted calls that are supplying us secrets to show in a tooltip. … The expectation here is that if the tooltip data function doesn't accept secrets from tainted callers, **this call will error**."
> — `Interface/AddOns/Blizzard_SharedXMLGame/Tooltip/TooltipDataHandler.lua:462-469`

The same handler refuses the call up front when `canaccessallvalues(...)` is false (`:457-460`). So: **a refused predicate call is evidence that the value is secret**, and a `pcall` around it turns that refusal into `ok = false`.

### 4.2 The canonical predicate

```lua
function TT.isSecretValue(v)
    if (type(v) == "nil") then return false end
    if (type(issecretvalue) == "function") then
        local okSecret, isSec = pcall(issecretvalue, v)
        -- A refused call is not "no": it is the engine refusing to test a secret
        -- from tainted code, which is itself proof that v is secret.
        if (not okSecret or isSec == true) then return true end
    end
    local canaccess = rawget(_G, "canaccessvalue")
    if (type(canaccess) == "function") then
        local okAccess, canAcc = pcall(canaccess, v)
        if (not okAccess or canAcc == false) then return true end
    end
    return false
end
```

`main.lua:245-257` is the shipped form of exactly this function.

### 4.3 The weak form is a defect, stated plainly

```lua
-- WRONG. On a secret value pcall returns false, isSec is nil, and this
-- expression says "not secret" — so the caller then boolean-tests or compares
-- the very value it just failed to classify.
if (okSecret and isSec) then return true end
```

Any guard written as `okSecret and isSec` (or `ok and isSec == true` without the `not ok` arm) inverts the one case it exists for: the *throwing* case. It reads as "not secret" precisely when the value is secret.

### 4.4 Where the strong form lives in this tree

All six copies of the predicate in the shipped tree use the strong form. Four of them — `main.lua`, `pawn.lua`, `TacoTip_Extras/Core.lua` and `TacoTip_Extras/RankBrowser.lua` — were already strong at the committed HEAD; the other two, `gearscore.lua` and `Libs/LibForeverInspector/LibForeverInspector.lua`, still carried the weak `okSecret and isSec` shape there, and the 2026-11-10 working-tree fixes align them. Extras call sites that used to test `issecretvalue` inline now call the already-strong helpers (`Core.IsSecretValue`, and `RankBrowser.lua`'s local `isSecretValue`).

| Copy | Location |
| :--- | :--- |
| `TT.isSecretValue` | `main.lua:245` (strong arm at `:249`) |
| `gearscore.lua` file-local | `gearscore.lua:216` (strong arm at `:220`) |
| `pawn.lua` file-local | `pawn.lua:80` (strong arm at `:84`) |
| `LibForeverInspector` file-local | `Libs/LibForeverInspector/LibForeverInspector.lua:78` (strong arm at `:82`) |
| `Core.IsSecretValue` | `TacoTip_Extras/Core.lua:61` (strong arm at `:65`) |
| `RankBrowser.lua` file-local | `TacoTip_Extras/RankBrowser.lua:18` (strong arm at `:22`) |

A review of this document or of the code must treat any new `pcall(issecretvalue, …)` site as suspect until its arms match §4.2.

### 4.5 The engine error text is a symptom, not a quoted contract

The previous revision printed this as client truth:

```
attempt to perform boolean test on a secret boolean value (execution tainted by 'TacoTip')
```

**That exact string does not appear anywhere in the client Lua on `origin/forever`** (grepping the whole tree returns nothing; the only near-matches are unrelated comments, e.g. `Blizzard_EncounterTimeline/EncounterTimelineTemplates.lua:144`). The same is true of `bad argument #1 … Secret values are only allowed during untainted execution`. Both are **observed runtime symptoms** — what the operator sees in the error frame — not strings quoted from the client source. Treat them as evidence that a secret value reached a boolean test or a `SecretArguments` check, and as the search key for a bug report; do not cite them as if the client documented them.

What *is* documented is the rule that produces them: `SecretArguments = "AllowedWhenUntainted"` (§4.1) and the `SecretWhen*` return predicates (§2.3).

---

## 5. The `safeUnitIsUnit` pattern

### 5.1 Why `UnitIsUnit` needs its own guard

`UnitIsUnit` carries three annotations (`UnitDocumentation.lua:2410-2414`):

```lua
Name = "UnitIsUnit",
Type = "Function",
RequiresComparableUnitTokens = true,
SecretWhenUnitComparisonRestricted = true,
SecretArguments = "AllowedWhenUntainted",
```

Two separate hazards follow, and the previous revision only knew about the second:

1. **`RequiresComparableUnitTokens`** — the precondition is checked against the *pair* of tokens. Its predicate documentation says guarded APIs "only accept unit token pairs that can be compared with one another. For example, comparisons where either unit is 'player' or 'target' are permitted, but comparisons between 'nameplate3' and 'boss1' are not", and its `FailureMode` is `"ReturnNothing"` (`SecretPredicatesDocumentation.lua:10-13`). The sanctioned pre-check is `C_Secrets.CanCompareUnitTokens(a, b)` (`SecretPredicateAPIDocumentation.lua:12-26`), which answers with a plain `bool`.
2. **`SecretWhenUnitComparisonRestricted`** — the returned boolean can itself be secret ("Comparisons involving compound unit tokens (eg. 'boss1target') are always secret. This restriction only applies when the player is on an addon-restricted map", `SecretPredicatesDocumentation.lua:120-122`). `pcall` guards the *call*; it does not make `isUnit == true` on a secret answer legal.

### 5.2 The shipped guard

`gearscore.lua:240`, `pawn.lua:104` and `Libs/LibForeverInspector/LibForeverInspector.lua:117` now carry the same helper:

```lua
local function safeUnitIsUnit(unit1, unit2)
    if (type(unit1) == "nil" or type(unit2) == "nil" or type(UnitIsUnit) ~= "function") then
        return false
    end
    if (isSecretValue(unit1) or isSecretValue(unit2)) then
        return false
    end
    -- RequiresComparableUnitTokens: ask before comparing. The namespace is a
    -- client capability the add-on must not assume; feature-detect it.
    local secretsApi = rawget(_G, "C_Secrets")
    local canCompareUnitTokens = type(secretsApi) == "table" and secretsApi.CanCompareUnitTokens
    if (type(canCompareUnitTokens) == "function") then
        local compareOk, permitted = pcall(canCompareUnitTokens, unit1, unit2)
        if (not compareOk or isSecretValue(permitted) or permitted == false) then
            return false
        end
    end
    local ok, isUnit = pcall(UnitIsUnit, unit1, unit2)
    if (not ok or isSecretValue(isUnit)) then
        return false
    end
    return isUnit == true
end
```

Three properties are load-bearing and must survive any rewrite:

- **A refusal is `false`, and `false` means "not verified equal", never "not equal".** Callers are written so that the answer only *skips a shortcut*: the GUID equality checks behind it (`safeUnitGUID` + `safeEquals`) remain authoritative. In `TT_GS:GetScore` and `TT_PAWN:GetScore` the self check is `safeUnitIsUnit(unitorguid, "player")`, and a readable GUID comparison still resolves self when the comparison is refused.
- **The comparison is never attempted when it cannot be verified.** A throwing `CanCompareUnitTokens`, a `permitted == false`, a secret token, or a secret `permitted` all return before `UnitIsUnit` is called.
- **The `UnitIsUnit` answer is secret-tested before it is boolean-tested.** `return isUnit == true` is reached only when the value is not secret.

`main.lua:306` holds the older `TT.safeUnitIsUnit`, which predates the `CanCompareUnitTokens` pre-check; it secret-tests both tokens and the answer and is otherwise unchanged. The one `UnitInRaid` call site in the shipped code is `main.lua:2903`, and it goes through `TT.safeUnitInRaid` (`main.lua:332`), which exists because `UnitInRaid` carries `SecretWhenUnitIdentityRestricted` (`OLD/main.lua` is not shipped and is not part of this statement).

### 5.3 The predicate contract, summarised

| Question | Sanctioned API | What a refusal means |
| :--- | :--- | :--- |
| "Can this pair be compared at all?" | `C_Secrets.CanCompareUnitTokens(a, b)` (`SecretPredicateAPIDocumentation.lua:12-26`) | Do not call `UnitIsUnit`; fall back to GUID equality. |
| "Is this value secret?" | `issecretvalue` / `canaccessvalue` behind `pcall`, strong form (§4) | `ok = false` **is** "secret". |
| "Is this restriction active right now?" | `C_RestrictedActions.IsAddOnRestrictionActive(type)` (§2.1) | `false` during the state-change dispatch — do not act on it mid-event. |
| "Does this build have secrets at all?" | `C_Secrets.HasSecretRestrictions()` (§2.2) | Build capability only; never a per-moment answer. |

---

## 6. Tooltip contract on Forever

The tooltip pipeline is secure code, and the add-on's only sanctioned entry point is the post-call hook. This is the contract the loot-window rule (§7) and the row-injection path both depend on.

- **`TooltipDataHandlerMixin:ProcessInfo(info)` is `securecallfunction`** — `Interface/AddOns/Blizzard_SharedXMLGame/Tooltip/TooltipDataHandler.lua:241-243`:

  ```lua
  function TooltipDataHandlerMixin:ProcessInfo(info)
      return securecallfunction(self.InternalProcessInfo, self, info);
  end
  ```

  It runs `InternalProcessInfo` (`:245`) untainted on purpose, so that tainted callers cannot make the secure path run tainted. **Hooking `ProcessInfo` re-taints exactly the function Blizzard wrapped. Do not hook it.**

- **Add-on callbacks are wrapped with `forceinsecure`** — `TooltipDataProcessor.AddTooltipPostCall` eventually stores the add-on function through `AddCall`, which for an insecure caller wraps it (`AddCall` at `TooltipDataHandler.lua:181-193`; the wrapper is `:187-190`):

  ```lua
  local function InsecureCallback(...)
      forceinsecure();
      return func(...);
  end
  ```

  So a registered post-call runs **insecurely by design**: it is allowed to read what the secure pipeline produced, and it is deliberate that it cannot be treated as secure code. This is the sanctioned hook, and TacoTip registers its extra-row callbacks through it (`main.lua:3738` for the unit tooltip, `main.lua:3960` for the item tooltip).

- **The rest of the pipeline is secure and must not be hooked:** `InternalProcessInfo` (`:245`), `GetPrimaryTooltipInfo` (`:393`), `AddLineDataText` (`:338`), and the accessor delegates built by `AddTooltipDataAccessorDelegate` (`:488-517`). Each of these either runs inside `securecallfunction` or is the function that decides how a secret line is rendered; a tainted hook there is what makes a tooltip render **no lines at all** (`GameTooltip.lua:994-1002` documents that combination explicitly).

- **Never mutate `lineData`.** The line tables handed through the pipeline carry secret text/aspect fields; writing to them, replacing them, or reading them for a decision is the second half of the blank-tooltip failure Blizzard describes in the same comment block.

- **Never restyle the loot tooltip.** It rebuilds itself every frame from the client's own data (§7); a font pass, width cap, backdrop or extra row there is applied to a tooltip whose lines are secret.

---

## 7. Loot Window Native Integrity Architecture

On WoW Forever, loot tooltips for unawarded items contain client-side secret lines. `GameTooltip.lua:994-1002` states that taint reaching `ProcessInfo`, combined with secret line data/text, can make the tooltip display no lines at all.

### 7.1 How the loot tooltip is built (verified at the pin)

- `GameTooltip:SetLootItem(slot)` is an entry in the accessor table (`TooltipDataHandler.lua:537`, `SetLootItem = "GetLootItem"`; the roll variant at `:538`), installed by `AddTooltipDataAccessorDelegate` (`:488-517`). The delegate is a `CreateSecureDelegate` whose own comment says the call runs "untainted, and taint is removed from all supplied arguments" (`:495-497` — the `CreateSecureDelegate` call at `:495` and the two comment lines at `:496-497`).
- The loot element rebuilds its tooltip every frame while the tooltip is owned: `LootFrame.lua:464-469` installs an `OnUpdate` that re-enters `OnEnter`, and the item tooltip itself is requested at `LootFrame.lua:630` (`GameTooltip:SetLootItem(self:GetSlotIndex())`).
- Therefore the tooltip is **re-created continuously** from secret-capable data. Any add-on pass that alters it can only ever be wrong for one frame at a time.

### 7.2 Frames hierarchy and detection matrix

| Frame type | Frame names / elements | Owner object / properties | Detection strategy |
| :--- | :--- | :--- | :--- |
| **Corpse loot** | `LootFrame`, loot item elements | `owner.GetSlotIndex`, `owner.GetItemSlotType` | Function presence on owner |
| **Group loot roll** | `GroupLootFrame1` … `4`, `GroupLootContainer` | `owner.rollID`, `owner:GetParent().rollID` | `rollID ~= nil` on owner or parent |
| **Bonus roll** | `BonusRollFrame`, `BonusRollLootWonFrame` | Frame name contains `BonusRoll` | Name pattern match |
| **Loot history** | `LootHistoryFrame`, `LootHistoryItem` | Frame name contains `LootHistory` | Name pattern match |
| **Master looter** | `MasterLooterFrame` | Frame name contains `MasterLoot` | Name pattern match |

The matrix is implemented as `isForeverLootTooltip` (`main.lua:2590-2625`), tried in this order: the two slot mixin methods on the owner, then `owner.rollID` / `parent.rollID`, then the frame-name patterns. Detection is by the owner object, **not** by reading the tooltip's tooltip-data table — that read is itself one of the reads Blizzard guards.

When `isForeverLootTooltip(tooltip)` returns `true`:

1. `itemToolTipHook` returns before `clearTooltipVisuals`, before any `C_Item` query, and before adding `Item Level`, `GearScore` or `HunterScore` rows.
2. `onTooltipShow` skips `tooltip.GetItem`, `resolveTooltipUnit` and `TooltipUtil.GetDisplayedUnit` reads for that tooltip.
3. The loot tooltip stays native Blizzard code with no add-on taint in it.

A normal item tooltip (bags, character frame, chat link, shopping, item ref) is unaffected and keeps the add-on's rows.

---

## 8. Centralized safe helper standards for TacoTip

These are the shipped helpers (`main.lua:245-356`), reproduced so a future edit has one canonical shape to match. Comment lines are shortened here; the code lines are identical to the tree. Their contract is: **refuse rather than throw, and answer "unknown" rather than "true"**.

```lua
-- Strong secret-value probe (see §4). A refused predicate call is "secret".
function TT.isSecretValue(v)
    if (type(v) == "nil") then return false end
    if (type(issecretvalue) == "function") then
        local okSecret, isSec = pcall(issecretvalue, v)
        if (not okSecret or isSec == true) then return true end
    end
    local canaccess = rawget(_G, "canaccessvalue")
    if (type(canaccess) == "function") then
        local okAccess, canAcc = pcall(canaccess, v)
        if (not okAccess or canAcc == false) then return true end
    end
    return false
end
local isSecretValue = TT.isSecretValue

-- Safe equality: a secret operand is never compared.
function TT.safeEquals(a, b)
    if (type(a) == "nil" or type(b) == "nil" or isSecretValue(a) or isSecretValue(b)) then
        return false
    end
    local ok, eq = pcall(function() return a == b end)
    return ok and eq == true
end
local safeEquals = TT.safeEquals

-- Safe UnitGUID: nil when the unit or the answer is secret.
function TT.safeUnitGUID(unit)
    if (type(unit) == "nil" or isSecretValue(unit) or type(UnitGUID) ~= "function") then return nil end
    local ok, guid = pcall(UnitGUID, unit)
    if (not ok or not guid or isSecretValue(guid)) then return nil end
    return guid
end
local safeUnitGUID = TT.safeUnitGUID

function TT.safeUnitExists(unit)
    if (type(unit) == "nil" or isSecretValue(unit) or type(UnitExists) ~= "function") then
        return false
    end
    local ok, exists = pcall(UnitExists, unit)
    if (not ok or isSecretValue(exists)) then
        return false
    end
    return exists == true
end
local safeUnitExists = TT.safeUnitExists

function TT.safeUnitIsPlayer(unit)
    if (type(unit) == "nil" or isSecretValue(unit) or type(UnitIsPlayer) ~= "function") then
        return false
    end
    local ok, isP = pcall(UnitIsPlayer, unit)
    if (not ok or isSecretValue(isP)) then
        return false
    end
    return isP == true
end
local safeUnitIsPlayer = TT.safeUnitIsPlayer

function TT.safeUnitIsUnit(u1, u2)
    if (type(u1) == "nil" or type(u2) == "nil" or isSecretValue(u1) or isSecretValue(u2) or type(UnitIsUnit) ~= "function") then
        return false
    end
    local ok, isU = pcall(UnitIsUnit, u1, u2)
    if (not ok or isSecretValue(isU)) then
        return false
    end
    return isU == true
end
local safeUnitIsUnit = TT.safeUnitIsUnit

function TT.safeUnitInParty(unit)
    if (type(unit) == "nil" or isSecretValue(unit) or type(UnitInParty) ~= "function") then
        return false
    end
    local ok, inP = pcall(UnitInParty, unit)
    if (not ok or isSecretValue(inP)) then
        return false
    end
    return inP == true
end
local safeUnitInParty = TT.safeUnitInParty

-- UnitInRaid returns a luaIndex (SecretWhenUnitIdentityRestricted), so the
-- "true" answer can be a positive number as well as a boolean.
function TT.safeUnitInRaid(unit)
    if (type(unit) == "nil" or isSecretValue(unit) or type(UnitInRaid) ~= "function") then
        return false
    end
    local ok, inR = pcall(UnitInRaid, unit)
    if (not ok or isSecretValue(inR)) then
        return false
    end
    return type(inR) == "number" or inR == true
end
local safeUnitInRaid = TT.safeUnitInRaid

function TT.safeUnitIsPVP(unit)
    if (type(unit) == "nil" or isSecretValue(unit) or type(UnitIsPVP) ~= "function") then
        return false
    end
    local ok, isPVP = pcall(UnitIsPVP, unit)
    if (not ok or isSecretValue(isPVP)) then
        return false
    end
    return isPVP == true
end
local safeUnitIsPVP = TT.safeUnitIsPVP
```

### 8.1 The file-local variants

`gearscore.lua`, `pawn.lua`, `LibForeverInspector` and TacoTip Extras cannot call `TT` helpers at file scope (load order, and the libraries must stay standalone), so each carries its own `isSecretValue` plus the `safeUnitIsUnit` of §5.2. The copies are listed in §4.4 and must stay byte-equivalent in behaviour to `TT.isSecretValue`; a change to one is a change to all six.

### 8.2 The rules that keep this correct

1. **Guard the argument as well as the return.** `SecretArguments = "AllowedWhenUntainted"` refuses a secret *input*; a `pcall` around the call is what turns that into a value the add-on can handle.
2. **Never let a secret value become a table key, a comparison operand, or a boolean test.** Those are the three shapes the reported errors take.
3. **Degrade to unknown.** A refused read means "no row" or "score unknown", never `0` presented as a real value, and never `true` presented as a verified answer.
4. **Do not add a seventh copy of the predicate.** If a new file needs one, it must reuse an existing helper or import the library's.
5. **Re-verify against the pin, not against memory.** Every claim in this file is tied to `1.60.1.70888` / `4cd0ab752`; when the client moves, the line numbers move with it.
