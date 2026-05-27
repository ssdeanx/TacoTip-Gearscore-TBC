# Feature Context

Use this template for planning the TacoTip library update work.

## Feature

- Name: Lib-update
- Owner: TBD
- Date: 2026-05-27
- Status: Draft

## Problem

- The bundled support libraries need to stay compatible with Classic-era TacoTip without breaking load order or runtime globals.

## Scope

### In scope

- Review bundled library manifests and Lua files.
- Keep load order aligned with `TacoTip.toc`.
- Preserve current addon behavior while updating library internals or metadata.

### Out of scope

- Rewriting tooltip features unrelated to library maintenance.
- Changing user-facing behavior unless a library change requires it.

## Environment

- WoW client family / interface version: Classic Era / TBC Classic Anniversary / Wrath Classic
- Required libraries: LibStub, CallbackHandler-1.0, LibDetours-1.0, LibClassicInspector
- Optional integrations: Pawn

## Relevant files

- `TacoTip.toc`
- `Libs/LibStub/*`
- `Libs/CallbackHandler-1.0/*`
- `Libs/LibDetours-1.0/*`
- `Libs/LibClassicInspector/*`
- `main.lua`
- `options.lua`
- `gearscore.lua`
- `pawn.lua`

## Current behavior

- The addon loads bundled libraries before the feature modules and expects the same global wiring at runtime.

## Notes / assumptions

- Keep any library refresh backward compatible with the Classic addon path.
