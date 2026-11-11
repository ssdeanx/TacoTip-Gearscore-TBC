# 2026-11-10 — Unit / Item secret-contract audit (session record)

Scope: **main TacoTip addon only.** `TacoTip_Extras/` was excluded by operator instruction.
Version: **stays `1.0.0`** — this work folds into the existing token, no bump.
Tree: branch `main`, base `bf08e71`, working tree uncommitted by design.

## The question this session answered

In instanced combat and encounters, users report Lua errors on loot-window item tooltips and on the
tooltip GearScore row. The hypothesis was that the add-on is reading an API whose documented return
shape it does not honour — a possibly-secret value compared, indexed, used as a key, or passed as an
argument to a function that refuses secrets from add-on code.

## Outcome

- **119** Unit/Item call sites audited across `main.lua`, `options.lua`, `gearscore.lua`, `pawn.lua`
  and `Libs/LibForeverInspector/LibForeverInspector.lua`.
- **97 already correct**, **22 corrected** at **21 sites**.
- **13 defects reproduce as failures on `HEAD`** under the new pins, so the corrections are proven
  rather than asserted.
- All 8 release gates pass (see below).

## Method

1. **Ledger first.** Every call site enumerated by identifier scan — not by grepping `(`, because most
   Unit calls are passed to `pcall`. Call forms covered: `Fn(...)`, `pcall(Fn, ...)`, `_G.Fn`,
   file-scope aliases (`local UnitClass = _G.UnitClass`, `fnUnitGUID`, `getItemInfo`), and
   `ItemLocation` methods (`item:GetItemLink()`), which are the mixin sugar over `C_Item.GetItemLink`.
   Output: `bench/audits/2026-11-10-api-contract-ledger.md`.
2. **Three per-file audits**, each owning one file and reading its contract out of
   `Blizzard_APIDocumentationGenerated/{Unit,Item}Documentation.lua`.
3. **Independent review** that re-derived 60 contracts from the client mirror and read every diff hunk.
   Output: `bench/audits/2026-11-10-api-contract-review.md` — verdict **PASS**.
4. **Regression pins** with a throwing `issecretvalue` and refusal counters at `SecretArguments`
   boundaries.
5. **Release gates** run by a verifier that edited nothing.
   Output: `bench/audits/2026-11-10-release-gate-report.md`.

## The defects that mattered

| Site | Defect | Why it fired in instances |
| :--- | :--- | :--- |
| `LibForeverInspector` fallback shim (~4186) | called bare `GetItemInfo` | that global only exists after `Blizzard_DeprecatedItemScript` loads, which never happens on Forever or Retail → `attempt to call global 'GetItemInfo' (a nil value)` |
| `LibForeverInspector` `PlayerGUIDToUnitToken` (~4942) | bare `UnitExists(InspectFrame.unit)` | a secret token is refused by `SecretArguments = "AllowedWhenUntainted"` with an immediate Lua error |
| `LibForeverInspector` queue drain (~5996) | bare `UnitExists(unitHint)` | same hazard |
| `LibForeverInspector` `safeUnitGUID` | `not guid` on a possibly-secret result | comparison on a secret |
| `options.lua` leaderboard | `UnitGUID("player")` compared with `==`, no secrecy test | shipped because **no harness ever builds the dashboard** |
| `gearscore.lua` weapon slots | Item receivers indexed before the secrecy test the slot loop already applies | `C_Item.*` takes the receiver as a `SecretArguments` argument |
| `main.lua` power bar | possibly-secret `unit` passed into `UnitPowerType`/`UnitPowerMax`/`UnitPower` untested | argument hazard, separate from the return |
| `main.lua` colour/level lines | token guards added before `UnitCanAttack`/`UnitIsPlayer`/`UnitLevel` | argument hazard |
| `main.lua` misc | `safeUnitGUID` nilable test, `GetItemLinkByGUID` nilable test, `GetItemInfo` link secrecy tests, `UnitDistanceSquared` secrecy-before-nil | nil / secrecy ordering |

`pawn.lua` needed no correction; it inherits the corrected wrappers.

## What is proven, and what is not

**Proven:** every documented Unit/Item call site in the five files was read against the client mirror;
no secret token reaches a `SecretArguments = "AllowedWhenUntainted"` function; no reachable comparison,
index, arithmetic op or table key operates on a possibly-secret value; `Nilable` and `MayReturnNothing`
are handled; no diagnostic was silenced; the FojjiCore `GameTooltip` row block is byte-identical; the
Forever loot-window tooltip is still native.

**Not proven — do not claim otherwise:**

- **Not "100% secret safe".** The audit is static. It covers what is written, not what a future edit
  writes, and not any call reached through a table field other than the listed `_G.` aliases.
- **`LibForeverInspector` is in `.wowluarc.json`'s `library` set**, so `wowlua_ls` suppresses its
  diagnostics. Its evidence is a manual row audit plus probes, not the linter.
- **The `type(v) == "nil"` changes are behaviour-neutral for the documented `string|nil` shape.** A Lua
  mock cannot raise on `secret ~= nil` the way the engine can, so those pins are marked `SHAPE` and
  red-proofed against defect-shaped copies. They are regression traps, not engine-faithful proofs.
- **Engine behaviour of `== nil` on a secret is not provable from the docs.** We avoid it rather than
  characterise it.
- **Disposition-driven secrets are handled, not eliminated.** `SecretWhenUnitIdentityRestricted`,
  `...HealthMaxRestricted`, `...PowerMaxRestricted` and `...SpellCastRestricted` are documented as "when
  the unit isn't player-controlled", with **no combat clause**. A boss or a stranger is secret outside
  combat too, so a combat gate could never have covered them.
- Six residual observations from the review are recorded and **not fixed** — notably `main.lua:5340`
  using a possibly-secret `classFilename` as a table key (unreachable via the GUID coupling) and
  `LFI:4186` doing a `string.match` before its guard (unreachable while `Item.CreateFromItemLink`
  exists). Second symptoms get a line in the report, not an edit.

## Decisions taken

- **No combat/encounter gate.** Rejected: it would not cover the disposition-driven secrets that cause
  the reported errors, it hides GearScore exactly where players want it, and it is player-visible.
  If in-game testing shows an error the guards cannot prevent, gate that one call, not the feature.
- **Version stays `1.0.0`.** Recorded in `CHANGELOG.md` as folded into the existing token.
- **No `---@diagnostic disable` added.** The two in `LibForeverInspector` (`redundant-parameter`, lines
  3224/4591) are present in `HEAD` and out of scope.
- **`LibForeverInspector` stays in `library`** for now. Its diagnostics are suppressed; moving it out is
  a follow-up, not a pre-release change.

## Gates (final)

| Gate | Result |
| :--- | :--- |
| `luacheck .` | 0 warnings / 0 errors in 91 files |
| `bash Tests/harness/run_all.sh` | 75 invocations, 75 passed, 0 failed |
| `LUA=luajit bash Tests/harness/run_all.sh` | 75 invocations, 75 passed, 0 failed |
| `bash TacoTip_Extras/Tests/harness/run_all.sh` | 42/42, no regression |
| `bash Tools/verify_release.sh --worktree` | 8/8 PASS |
| `bash Tools/verify_release_extras.sh --worktree` | 9/9 PASS |
| `wowlua_ls check .` | 0 errors, 0 secret-value findings (551 pre-existing warnings) |
| no suppressions added | none |

## Operator in-game test

```
/console addonCombatRestrictionsForced 1
/console addonEncounterRestrictionsForced 1
```

Then hover a player, a boss and a party member; open a loot window; check the GearScore row. Neither
cvar persists across a restart. **In-game observation outranks every claim in this document.**

## Follow-ups (not done)

1. Move `LibForeverInspector` out of the `library` set so the linter can see it.
2. Harness coverage for the `/tt` dashboard (leaderboard rows + "My Rank") — its absence is why the
   `UnitGUID` defect shipped.
3. Resolve the six review residuals.
4. Add `---@secret-guard` annotations for any guard helper added later.
