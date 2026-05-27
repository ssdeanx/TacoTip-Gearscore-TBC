# PRD

## Problem statement

- What library maintenance problem are we solving?

## Goals

- Goal 1: keep bundled libraries compatible with supported Classic clients.
- Goal 2: preserve tooltip, inspect, and options behavior while refreshing library files or metadata.
- Goal 3: avoid regressions in load order, callbacks, or shared globals.

## Non-goals

- What is out of scope?
- Rewriting the addon UI or feature set unrelated to library maintenance.

## User stories

- As a player, I want TacoTip to keep working after library updates.
- As a maintainer, I want a predictable way to refresh bundled libraries without breaking load order.
- As a maintainer, I want to verify that optional Pawn behavior still stays optional.
- As a maintainer, I want library changes to be easy to review and test.
- As a player, I want no new errors in tooltips or inspect frames.

## Success criteria

- Success criteria should be specific, measurable, achievable, relevant, and time-bound (SMART).
- The addon loads without Lua errors on supported Classic clients.
- Tooltips, inspect data, and options UI behave the same after the library update.

## Constraints

- Limitations should be clearly defined.
- Preserve Classic-era compatibility.
- Preserve the current `TacoTip.toc` load order.
- Keep optional Pawn support optional.
