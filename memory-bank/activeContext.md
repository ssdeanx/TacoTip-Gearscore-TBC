# Active Context

Current focus:

- Keep TacoTip loading cleanly on Burning Crusade Classic Anniversary `2.5.5` / `Interface 20505`.
- Preserve the verified Classic-era scope and the actual load order from `TacoTip.toc` while reducing bundled-lib warning noise.

What has been confirmed:

- The addon supports Classic Era / TBC Classic Anniversary / Wrath Classic only (`Interface` 11508 / 20505 / 30405).
- `TacoTip.toc` loads bundled libs first, then `gearscore.lua`, `pawn.lua`, `options.lua`, and `main.lua`.
- Core runtime modules share globals: `TT`, `TT_GS`, `TT_PAWN`, `TacoTipConfig`, and `TACOTIP_LOCALE`.
- Pawn support is optional and gated by `PawnClassicLastUpdatedVersion >= 2.0538`.
- The public patch reference for Burning Crusade Classic Anniversary `2.5.5` confirms `Interface .toc = 20505`.
- `options.lua` now intentionally overrides the bootstrap slash handler so the final `/tacotip` command set is owned by the options module.
- `LibClassicInspector.lua` now guards its load-time tickers and detours so missing client globals do not abort addon startup.
- `LibDetours-1.0.lua`, `LibStub.lua`, and `CallbackHandler-1.0.lua` were cleaned up so luacheck can inspect the bundled libs without broad folder exclusion.
- Targeted post-change diagnostics on the edited files are clean; the remaining verification step is an in-game TBC Anniversary smoke test.
- `options.lua` now guards every `RefreshPosition()` call in `resetCfg()`.
- `main.lua` now binds `tinsert` to `table.insert` so the tooltip target-display path is safer on clients with missing globals.
- Web research confirms the addon options panel can still be built as a normal `Frame` with named widget templates like `InterfaceOptionsCheckButtonTemplate`, `UIDropDownMenuTemplate`, `UIPanelButtonTemplate`, `InputBoxTemplate`, and `UIPanelScrollFrameTemplate`.
- Web research also confirms the safest cross-client options-menu strategy is dual-path registration: prefer `Settings.RegisterCanvasLayoutCategory` / `Settings.RegisterAddOnCategory` when present, otherwise fall back to `InterfaceOptions_AddCategory(panel)` and legacy open helpers.
- Legacy Interface Options opening in Classic-family clients can require `InterfaceOptionsFrame_Show()` plus `InterfaceOptionsFrame_OpenToCategory(panel)` and sometimes scroll assistance when the category is low in the addon list.

Current guidance for future sessions:

- Treat `README.md`, `TacoTip.toc`, `main.lua`, `options.lua`, `gearscore.lua`, `pawn.lua`, and `Libs/*` as source of truth.
- Keep updates small and consistent across the memory-bank files.
- If code and memory ever disagree, update the memory bank to match the code.
