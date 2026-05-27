# Changelog

All notable changes to TacoTip Remix will be documented in this file.

| Version | Date | Summary |
| --- | --- | --- |
| `0.4.8` | `2026-05-27` | TBC Anniversary startup hardening, slash-command ownership fix, and bundled-lib warning cleanup |
| `0.0.1` | `2026-05-18` | First public live release of TacoTip Remix |

## [0.4.8] - 2026-05-27

### Fixed (0.4.8)

- Hardened `LibClassicInspector` load-time ticker and detour setup so missing client globals no longer abort addon startup on TBC Anniversary.
- Fixed `LibDetours-1.0` unhook handling by defining the missing `nop` helper and guarding hook/detour targets before installing them.
- Let `options.lua` intentionally take ownership of the final `/tacotip` slash handler so reset/help/anchor commands are available after the bootstrap phase.
- Removed broad luacheck lib exclusions and cleaned bundled library warnings in `LibStub`, `CallbackHandler-1.0`, and `LibDetours-1.0`.

### Changed (0.4.8)

- Bumped TacoTip Remix version metadata to `0.4.8` to track the Anniversary compatibility pass.
- Updated `LibClassicInspector/API.txt` version header to match the embedded library revision.

## [0.0.1] - 2026-05-18

### Added

- Public release of TacoTip Remix as a revived fork of TacoTip.
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
