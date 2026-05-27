# Progress

## 2026-05-27

- Inspected the addon manifest, README, main modules, and bundled libraries.
- Confirmed the core wiring: LibStub → CallbackHandler-1.0 / LibDetours-1.0 / LibClassicInspector, then TacoTip modules.
- Captured the Classic-era client gate, optional Pawn integration, tooltip hook flow, and options/UI bootstrap behavior.
- Drafted and saved a detailed implementation plan in `/memories/session/plan.md`.
- Implemented the TBC Anniversary startup hardening pass in `LibClassicInspector.lua` and `LibDetours-1.0.lua`.
- Fixed the final slash-command ownership so `options.lua` now overrides the bootstrap `/tacotip` handler with the full command set.
- Removed the broad bundled-lib luacheck exclusions and cleaned the main library warnings in `LibStub.lua`, `CallbackHandler-1.0.lua`, and `LibDetours-1.0.lua`.
- Updated version/docs tracking to `0.4.8` across `TacoTip.toc`, README, changelog, and the `LibClassicInspector` API header.
- Re-ran targeted diagnostics on the edited library/runtime/docs files; all checked files are now clean.
- Hardened `options.lua` reset handling by guarding every `RefreshPosition()` call with method existence checks.
- Bound `main.lua`'s `tinsert` usage to `table.insert` so the tooltip path no longer depends on a possibly-missing global alias.
- Researched TBC/Classic-friendly options UI patterns on the web and confirmed TacoTip can use Blizzard widget templates like `InterfaceOptionsCheckButtonTemplate`, `UIDropDownMenuTemplate`, `UIPanelButtonTemplate`, `InputBoxTemplate`, and `UIPanelScrollFrameTemplate` for a richer config screen.
- Confirmed the correct add-on menu registration strategy is to keep the existing dual-path approach: use `Settings.RegisterCanvasLayoutCategory` when available, otherwise register with `InterfaceOptions_AddCategory`.
- Confirmed legacy `InterfaceOptionsFrame_OpenToCategory` behavior can still need `InterfaceOptionsFrame_Show()` and occasional scroll-to-category workarounds on Classic-family clients.

### Status

- Memory bank implementation: updated with the Anniversary runtime and lint cleanup work
- Next step: upgrade `options.lua` into a fuller tabbed/sectioned configuration UI and tighten the options-menu open behavior for Classic/TBC clients
