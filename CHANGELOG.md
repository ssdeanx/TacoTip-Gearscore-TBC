# Changelog

All notable changes to TacoTip Gearscore TBC will be documented in this file.

| Version | Date | Summary |
| --- | --- | --- |
| `0.4.8` | `2026-05-27` | TBC Anniversary compatibility pass plus a professional multi-page options UI overhaul |
| `0.0.1` | `2026-05-18` | First public live release of TacoTip Gearscore TBC |

## [0.4.8] - 2026-05-27

### Fixed (0.4.8)

- Hardened `LibClassicInspector` load-time ticker and detour setup so missing client globals no longer abort addon startup on TBC Anniversary.
- Fixed `LibDetours-1.0` unhook handling by defining the missing `nop` helper and guarding hook/detour targets before installing them.
- Let `options.lua` intentionally take ownership of the final `/tacotip` slash handler so reset/help/anchor commands are available after the bootstrap phase.
- Removed broad luacheck lib exclusions and cleaned bundled library warnings in `LibStub`, `CallbackHandler-1.0`, and `LibDetours-1.0`.

### Changed (0.4.8)

- Kept the addon title aligned as `TacoTip Gearscore TBC` in metadata, docs, and the Blizzard AddOns/options tree entry.
- Updated `LibClassicInspector/API.txt` version header to match the embedded library revision.
- Rebuilt the options UI into a parent `TacoTip` category with `Tooltips`, `Positioning`, `Character & Inspect`, and `Advanced` child pages.
- Added a live tooltip preview, clearer positioning workflow, a custom-anchor dropdown, and numeric/slider offset controls for character and inspect overlays.
- Shipped the new options copy in `Locale/enUS.lua` first, relying on the existing locale fallback merge for untranslated locales.
- Added tooltip visual customization controls for class-tinted border/background styling, alpha, portrait display/scale, tooltip fonts, tooltip text size, and shared health/power bar textures with optional SharedMedia integration.
- Extended SharedMedia integration so tooltip background and border textures are discovered automatically from media packs and fall back to Blizzard tooltip assets when unavailable.
- Added Blizzard color-picker-backed border/background swatches, mouse-wheel support on scroll pages and sliders, clearer titled visual subsections, and stronger single-dropdown texture strip previews.
- Followed up with stability polish by moving the sparse Advanced toggles onto the root page, relocating the live preview into a dedicated right-side column, using clean collapsed dropdown titles, and keeping the custom tooltip anchor when resetting the mover position.

## [0.0.1] - 2026-05-18

### Added

- Public release of TacoTip Gearscore TBC as a revived fork of TacoTip.
- Restored Classic-era support after the original addon stopped working for TBC Classic.
- Updated Blizzard API wiring for the current Classic flavor families.
- Rebuilt the options panel, mover flow, and slash-command entry points.
- Added a CurseForge-ready Markdown README and changelog.

### Fixed

- LibClassicInspector load order and helper wiring.
- Bundled library TOCs and multi-flavor interface metadata.
- Tooltip mover, custom anchor, and options bootstrap wiring.
- Luacheck warnings in `LibClassicInspector.lua`.

### Notes

- This fork exists to keep TacoTip working again and to leave room for future features.
