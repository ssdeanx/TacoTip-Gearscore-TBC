# Verification Gates & Testing Protocol

## 1. Static Analysis (`luacheck` & `wowlua_ls`)

- `luacheck .` — Must report **0 warnings / 0 errors across all 70 files**. Never use inline `-- luacheck: ignore`; use dynamic indexing or local guards (`rawget(_G, ...)`).
- `wowlua_ls check . 2>&1 | grep -E "error" || echo "wowlua_ls: 0 errors"` — Must report **0 errors** (`.wowluarc.json` declares `classic_era`, `classic`, `forever`, `retail`; never add `"titanforge"`, which `wowlua-ls` rejects).

---

## 2. Offline Harness Suite (`Tests/harness/run_all.sh`)

Run under **both** Lua 5.1 and LuaJIT after edits:

- `bash Tests/harness/run_all.sh` → **75 / 75 invocations passed, 0 failed**
- `LUA=luajit bash Tests/harness/run_all.sh` → **75 / 75 passed, 0 failed**

Covers `detect_test`, `locale_test`, `font_test`, `specname_test`, `textures_test`, `load_test` (5 clients × `slot4`/`slot7` + missing `GameTooltip_SetDefaultAnchor`), `options_test` (5 clients + `legacy`/`nocolor`/`nofadeout` + dashboard & progression assertions), `settings_test` (5 clients × 4 modes), `fileguard_test`, `batch2_pawn_test`, `batch4_clock_test`, `batch8_pane_test`, `gearscore_test`, `tooltip_test`, `forever_tooltip_test` (217 Forever pins), `secretguard_test`, `custompos_test` (12 pins), `contract_pins_test`, `taint_test`, and `talent_check`.

### Harness Fidelity Lessons (0.8.3+)
1. Shim `xpcall` varargs (`xpcallWithArgs`) for stock Lua 5.1 so `CallbackHandler-1.0` delivers callback payloads.
2. Preserve `next` and all Lua stdlib symbols inside sandboxed `_G` wipes.
3. Always pass `(frame, event, ...)` when invoking frame script handlers directly.

---

## 3. Package Release Verifiers (Worktree Mode)

- `bash Tools/verify_release.sh --worktree` — **PASS** (core TacoTip `v1.0.6`, single `.toc`, consistent versions across `TacoTip.toc`/`main.lua`/`options.lua`/`README.md`, 5 interfaces, `logo.tga`).
- `bash Tools/verify_release_extras.sh --worktree` — Standalone verifier for `TacoTip_Extras/` (`v1.3.2`).
- Never stage or commit via git manually; only the verifiers invoke read-only git when run.
