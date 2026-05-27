# Design

## Summary

- Update the bundled support libraries while preserving current TacoTip behavior, Classic-era compatibility, and the existing load order.

## Architecture

- Modules touched: `TacoTip.toc`, `Libs/*`, and any addon modules that consume shared library behavior.
- New globals / data flow: avoid introducing new globals; preserve `TT`, `TT_GS`, `TT_PAWN`, and `TacoTipConfig`.
- Library dependencies: keep `LibStub`, `CallbackHandler-1.0`, `LibDetours-1.0`, and `LibClassicInspector` aligned.

## Data flow / UI flow

1. Load bundled libraries first through `TacoTip.toc`.
2. Let the addon modules reuse the existing shared library globals and callbacks.

## Risks

- Cache latency
- Classic API quirks
- Slash-command / load-order interactions
- Breaking the addon if a library manifest or load order changes unexpectedly

## Verification

- How to test in-game: load the addon on a supported Classic client, open tooltips, inspect a unit, and confirm no errors after a `/reload`.
