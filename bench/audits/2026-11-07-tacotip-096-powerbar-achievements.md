# TacoTip 0.9.6 — power bar secret values + Retail-only achievements (2026-11-07)

**Scope:** TacoTip root add-on, 0.9.6 working tree. `TacoTip_Extras` is a separate add-on and was not edited.
**Verdict:** both requests are implemented, pinned and gated. In-game verification is pending.

## Request

- "do we have it so power bars will pass secret data in wow forever when its turned on? if not it wont show."
- "disable achievements for wow forever ... only retail should have achievement points."
- "be careful not to mess up other clients. their power bar works."

## Client truth (VERIFIED, origin/-qualified)

| API | Classic Era / TBC / Titanforge | WoW Forever / Retail |
| :--- | :--- | :--- |
| `UnitPower` | no secret annotation | `SecretWhenUnitPowerRestricted = true`; `SecretArguments = "AllowedWhenUntainted"` |
| `UnitPowerMax` | no secret annotation | `SecretWhenUnitPowerMaxRestricted = true`; `SecretArguments = "AllowedWhenUntainted"` |
| `UnitPowerType` | `MayReturnNothing = true` | same, plus `SecretArguments = "AllowedWhenUntainted"` |
| `StatusBar:SetValue` / `SetMinMaxValues` | plain number args | `SecretArguments = "AllowedWhenTainted"`; `SecretArgumentsAddAspect = { Enum.SecretAspect.BarValue }` |
| `issecretvalue` | present | present |

Sources on each branch: `Interface/AddOns/Blizzard_APIDocumentationGenerated/UnitDocumentation.lua` (UnitPower/UnitPowerMax/UnitPowerType), `SimpleStatusBarAPIDocumentation.lua` (SetValue/SetMinMaxValues), `FrameScriptDocumentation.lua` (issecretvalue).

The old show gate was `UnitPowerMax(tooltipUnit) > 0`. On Forever/Live a restricted unit returns a **secret** max, which cannot be compared; the call raises and the bar never shows. The status bar itself accepts secret bar values, so the correct shape is: do not compare a secret max, show the bar, and pass `UnitPowerMax`/`UnitPower` through untouched to `SetMinMaxValues`/`SetValue`.

`GetTotalAchievementPoints` is a FrameXML global in `Blizzard_AchievementUI` on all five branches, but the product decision for 0.9.6 is Retail-only. The toggle is gated on `CI:IsRetail()` and the render path requires `isRetail`.

`issecretvalue` is a read-only client global. It is declared in `.luacheckrc` `read_globals`; the add-on does not define, replace or detour it.

## Changes

- `main.lua`: `tooltipUnitHasVisiblePower(unit)` returns true for a secret `UnitPowerMax` and otherwise keeps the original `max > 0` gate; the show branch uses it. The achievement render block requires `isRetail`.
- `options.lua`: the achievement toggle is enabled only for `CI:IsRetail()`; the disabled presentation on other clients is unchanged.
- `.luacheckrc`: declares `issecretvalue` as a read global with the client-doc citation.
- `Tests/harness/tooltip_test.lua`: four new checks (secret power shows/passes through; non-secret zero max still hides; achievement row on Retail only).
- `Tests/harness/settings_test.lua`: the achievement toggle gate now expects Retail only.
- No saved-variable shape change, no power-colour/event/anchor/padding change, no Extras edit.

## Pins and red proof

- Power, pre-fix `main.lua`: **3/204 FAILED** on Forever — `shown=false`, `max=nil`, and `main.lua:2947: attempt to compare number with table`.
- Zero-max over-correction mutant (`return true`): **1/204 FAILED** — `shown=true` when max is 0.
- Achievement render, pre-fix: **1/204 FAILED** on Forever (the row appears); Retail remains **204/204**.
- Old achievement gate in `options.lua`: `settings_test` **1/65 FAILED** on Forever and Titanforge (`enabled=true clientHas=false`); Retail **65/65**.
- Fixed tree: tooltip_test **204/204** on Forever/Retail, **198/198** on Classic/TBC/Titan; settings_test **65/65** on every client; options_test remains **79/79**.

## Gates (2026-11-07)

- `bash Tests/harness/run_all.sh`: **72/72** on lua5.1, lua5.4 and luajit.
- `luacheck .`: **0 warnings / 0 errors in 88 files**.
- `bash Tools/verify_release.sh --worktree`: **PASS**.
- `bash Tools/verify_release_extras.sh --worktree`: **PASS**.
- Version 0.9.6 is consistent across TOC, Lua fallbacks, README and the verifier.

## Operator in-game test (WoW Forever)

1. Enable the power bar in TacoTip options; hover a restricted player/unit and confirm the bar appears and tracks power. On Retail, repeat once to confirm the same secret path works there.
2. On a Classic client, confirm the power bar still appears and updates (non-secret path unchanged).
3. Open the options root page on Forever: the achievement-points toggle must be disabled. On Retail it must be enabled and still render the achievement row when checked.
4. Hover a player on Forever with a saved true `show_achievement_points`: no achievement row must appear.

## Not changed

- Power bar colour selection, event/ticker updates, anchors and padding; health bar; tooltip pipeline; saved-variable shapes; GearScore formula; inspect gates; FojjiCore row; `TacoTip_Extras`.
