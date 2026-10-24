# Verification Gates & Testing Protocol

## 1. Zero-Warning Luacheck Gate

- **Command:** `luacheck .`
- **Standard:** 0 warnings / 0 errors across all 21 repository files.
- **Rule:** Never use `-- luacheck: ignore` inline comments to suppress warnings. Use dynamic table indexing (e.g. `_G["WorldMapTooltip"]`, `GameTooltip["Method"]`) or local caching.

---

## 2. WoWUnit Test Suite (`TacoTip_Tests.lua`)

- **Invocation:** `/tttest` in-game or via local Lua runner mocks.
- **Suites Registered (9 total):**
  1. `TacoTip-Core`: Namespace loading, public API presence, version metadata, interface IDs.
  2. `TacoTip-Config`: Default keys, Shaman Blue override, boolean sanitization, numeric bounds.
  3. `TacoTip-Borders`: Class-color border painting, non-unit border isolation, SharedMedia resolution caching.
  4. `TacoTip-Portrait`: 3:4 aspect ratio (`66x88`), integer scaling (50%–200%), `OnUpdate` alpha sync tracking.
  5. `TacoTip-Guild`: Fallback parser regex, `<Guild> Rank` format, hide suppression.
  6. `TacoTip-Stats`: Nil-safe GearScore / Pawn calculations, `LibClassicInspector` presence, dual-spec reachability.
  7. `TacoTip-Mover`: Mover handle sync, options UI refresh nil-safety, custom position initialization.
  8. `TacoTip-Modules`: Dependent global exposure, default configuration parity.
  9. `TacoTip-MinimapAndAnchor`: Frame ownership preservation, mouse disablement on `GameTooltip_SetDefaultAnchor`.

---

## 2b. Offline Harness Fidelity Rules (`Tests/harness/`)

Learned the hard way in 0.8.3. The offline harness runs stock `lua5.1`, which is **not** the interpreter WoW ships. Three divergences already produced green tests that asserted nothing:

1. **`xpcall` varargs.** WoW's Lua accepts `xpcall(f, handler, ...)`; stock 5.1 accepts exactly two arguments. Blizzard's own FrameXML depends on it and so does `CallbackHandler-1.0` v7 `Dispatch`, which passes the event name and payload through it. `detect_test.lua` now shims it (`xpcallWithArgs`) so handlers receive their arguments. Without the shim every handler gets **zero** arguments.
2. **The wiped global environment must list every standard the bundled libs capture.** `run()` wipes all of `_G` and restores a fixed list. `next` was missing, so `CallbackHandler` captured `local next = nil` and **every `callbacks:Fire()` raised inside `Dispatch`** — invisibly, because no test fired a callback until 0.8.3.
3. **Frame scripts take `self` first.** `function(self, event, ...)`. Calling `handler("INSPECT_READY", guid)` puts the event name in the `self` slot, the branch never runs, and the assertion passes because nothing happened. Always pass the frame.

General rule: a harness that never exercises a code path cannot report on it, and `baseEnv`'s `CreateFrame` originally discarded `SetScript` handlers — making the whole event handler unreachable. Tests that need an event must supply a `CreateFrame` that retains scripts.

---

## 3. Mock Teardown Discipline

In tests, every global mock (e.g. `GetGuildInfo`, `UnitExists`, `GameTooltip.GetUnit`) must be cleaned up in a guaranteed teardown (`pcall` wrapper with `ClearReplaces()`) so subsequent test runs are never polluted.

---

## 4. Package Release Verifiers

- **Commands:**
  - `bash Tools/verify_release.sh --worktree`
  - `bash Tools/verify_release_extras.sh --worktree`
- **Standard:** Both must report PASS. Validates the working tree against release packaging allowlists, strictly excluding workshop files (`desks/`, `bench/`, `Tools/`, `OLD/`, `Tests/`), documentation dotfiles, and ensuring valid single-TOC structure.

---

## 5. Offline Test Runner Gate

- **Command:** `bash Tests/harness/run_all.sh`
- **Standard:** 71 passed, 0 failed across all 5 supported client families (`classicEra`, `tbc`, `titanforge`, `forever`, `retail`) and both `GetBuildInfo` return layouts (`slot4`, `slot7`).
