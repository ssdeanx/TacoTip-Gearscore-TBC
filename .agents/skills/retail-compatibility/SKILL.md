---
name: retail-compatibility
description: Guides TacoTip Retail-only feature gating and cross-client compatibility, used when disabling or restricting Retail features like achievement points on Forever, Titanforge, and Classic clients.
whenToUse: Use when adding a Live/Retail feature, disabling achievement points or another Retail-only feature on WoW Forever, Titanforge, or Classic, or when verifying Retail API presence per branch and pinning settings tests.
---

# Retail Compatibility Skill

Use this skill when developing features intended for Live (Retail) servers or when merging cross-client compatibility into TacoTip.

## Steps

1. **Verify achievement API presence per branch:**
   - Use the global constant WOW_PROJECT_ID to isolate execution paths. Retail is WOW_PROJECT_MAINLINE; all Classic Era, SoD, TBC Anniversary, Wrath, Titanforge, and Forever paths must stay separate.
   - Do not assume a Retail function exists elsewhere. Test for GetTotalAchievementPoints presence before calling it outside a strict Retail branch.
   - Record presence per branch: the achievement API exists on Retail only. It does not exist on Forever, Titanforge, or Classic, where clientHas is false.
2. **Gate main display to Retail only:**
   - In main.lua, place achievement-points display behind the Retail check only, so GetTotalAchievementPoints is not called or displayed on Forever, Titanforge, or Classic.
   - Preserve other clients: do not change power-bar or other feature behavior when applying this gate. Keep secret-safe UnitPowerMax handling unchanged.
3. **Gate options toggle to Retail only:**
   - In options.lua, enable the achievement-points toggle only where the feature exists (Retail). On non-Retail clients the toggle must be disabled or hidden so enabled matches actual API presence.
   - Integrate Retail UI state into the existing TT global object. Do not create new top-level globals for Retail-only data.
4. **Pin the settings test:**
   - Run and keep the settings pin achievement-points toggle is enabled exactly where the feature exists in Tests/harness/settings_test.lua, asserting toggle enabled equals per-branch API presence.
   - Run lua5.1 Tests/harness/settings_test.lua per client context (Retail 120105, Forever 16001, Titanforge 38002). Mock WOW_PROJECT_ID for the intended client and restore it in tear-down, specifying the client context for WoWUnit tests.
5. **Prove the old gate fails and the new gate passes:**
   - Against the old gate, confirm the pin fails on Forever and Titanforge with enabled=true while clientHas=false, and passes on Retail.
   - Against the new gate, confirm the pin passes on Retail, the toggle is disabled on non-Retail, and GetTotalAchievementPoints is not called there.
6. **Run the full gates with no non-Retail regression:**
   - Run bash Tests/harness/run_all.sh, then repeat with LUA=lua5.4 and LUA=luajit, and run luacheck .
   - Expected result: 72 invocations pass on each interpreter and luacheck reports 0 warnings / 0 errors, matching the main suite count.

## Pitfalls

- Achievements were previously enabled on WotLK, Forever, and Retail. A broad enablement leaks a Retail feature onto non-Retail clients. Always restrict to Retail unless the request explicitly expands it.
- The old toggle gate returned enabled=true where clientHas=false on Forever and Titanforge. The pin must compare enabled to actual API presence, not to a stale client list.
- Calling GetTotalAchievementPoints on a client without the API errors or displays invalid points. Verify presence per branch before calling.
- Restricting achievements must not alter power-bar or other client behavior. Other clients' power bar works and must stay unchanged. Keep secret-safe handling and unrelated gates intact.
- Testing Retail logic without specifying client context or without restoring WOW_PROJECT_ID leaks branch state. Mock per test and restore in tear-down.

## Verification

- Main display and options toggle are gated to Retail only. GetTotalAchievementPoints is not called or displayed on Forever, Titanforge, or Classic.
- The settings pin achievement-points toggle is enabled exactly where the feature exists passes on Retail and fails on Forever and Titanforge against the old gate.
- Full run_all gates pass across lua5.1, lua5.4, and luajit with 72 invocations each, luacheck reports 0 warnings / 0 errors, and no non-Retail regression occurs, including power bar.
