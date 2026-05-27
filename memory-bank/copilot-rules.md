# Copilot Rules

- Keep every change compatible with Classic-era clients only; preserve the `GetBuildInfo()` major-version gate.
- Treat `README.md`, `TacoTip.toc`, and the Lua entrypoints as the source of truth.
- Preserve the bundled-library model; do not replace or bypass `LibStub`, `LibClassicInspector`, or `LibDetours-1.0` without a strong reason.
- Keep `TacoTipConfig` defaults and config keys aligned across code and documentation.
- Respect the optional nature of Pawn support and do not assume it is installed.
- Avoid breaking tooltip hooks, anchoring, or slash commands when making UI changes.
- Update the memory bank when the codebase meaningfully changes.
