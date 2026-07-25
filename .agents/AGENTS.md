# Workspace Rules: TacoTip-Gearscore-TBC

## Strict Quality & Linting Gates
- **NEVER bypass Luacheck:** Do not use `-- luacheck: ignore` comments to silence warnings (like warning 122). If a global mutation causes a warning (e.g., field mutation on `GameTooltip`), use dynamic table access (`GameTooltip["MethodName"]`) or proper mocking libraries to resolve it cleanly.
- **Zero-Warning Tolerance:** All new code must pass static analysis without introducing new warnings.
- **No Destructive Overrides:** Do not overwrite Blizzard API globals in runtime code. If doing so in tests, ensure original states are restored securely via `pcall` or robust tear-downs.

## Retail/Live Feature Architecture
- **Version Isolation:** When introducing Live (Retail) features, use strict `WOW_PROJECT_ID` checks (e.g., `WOW_PROJECT_MAINLINE`). Do not bleed Retail-specific API calls into the Classic execution path.
- **Fallback Gracefully:** If a Live API is missing in a Classic client (or vice versa), the addon must fail gracefully without throwing Lua errors to the user.

## Autonomous Workflow Safety
- **Ask Before Deleting:** Never delete existing `.lua` files or remove legacy UI elements without explicit user approval.
- **Test-Driven Modifications:** Before modifying critical path code (like `TT:ApplyTooltipAppearance`), write a `WoWUnit` test to prove the current state, apply the modification, and verify the test passes.
