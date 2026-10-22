# fix-extras-final-review — Journal

## 2026-10-20 — Desk opened
- **Purpose:** The TacoTip **Extras** side of the four findings from the final
  release review of TacoTip Extras 1.2.3.
- **Scope:** `TacoTip_Extras/RankBrowser.lua`, `TacoTip_Extras/Locale/*.lua`
  (all 11), `TacoTip_Extras/CHANGELOG.md`, `TacoTip_Extras/Tests/harness/load_test.lua`.
  **NOT** the main add-on's code — another lane owns the main side of item 1
  (the `/tt` forwarding). No commit, no staging.
- **Baseline measured (not assumed):** Extras harness `TOTAL 42 invocations:
  42 passed, 0 failed` (lua5.1 / lua5.4 / luajit); `cd TacoTip_Extras &&
  luacheck .` → `Total: 0 warnings / 0 errors in 26 files`;
  `bash Tools/verify_release_extras.sh` → `verify_release_extras: PASS`; the
  main add-on's harness → `TOTAL 70 invocations: 70 passed, 0 failed`.

## 2026-10-20 — Items 1-4 done, pinned, revert-proven
- **Item 1 — the leaderboard toggle is published on a plain global.**
  `RankBrowser.lua:2852-2860`: a file-scope `toggleLeaderboard()` that calls
  `RankBrowser.Toggle()` at CALL time is published as
  `_G.TacoTipExtrasToggleLeaderboard` and is ALSO the function registered as
  `SlashCmdList.TACOTIPRANKS` (`RankBrowser.lua:2857-2860`) — the same
  function OBJECT, not a copy, so the two cannot drift.
  **Why the global is needed (VERIFIED against the client source on the local
  `wow-ui-source` checkout):** `SlashCmdList` is a proxy table —
  `Blizzard_ChatFrameBase/Shared/ChatFrameSetup.lua:3-4` does
  `setmetatable(list, { __index = {} })` and line 11 applies it to
  `_G.SlashCmdList`; `ChatFrameUtil.lua:717-736` (`ImportListToHash`) moves
  every handler into `getmetatable(list).__index` (line 732) and then WIPES the
  real table (line 735, `securecallfunction(tWipe, list)`); and
  `ChatFrameEditBox.lua:245, 257, 259` imports and dispatches immediately
  afterwards. So `rawget(SlashCmdList, "TACOTIPRANKS")` at dispatch time is nil.
  The existing `SlashCmdList.TACOTIPRANKS` registration is kept, and the
  single-token aliases (`/ttrank`, `/ttranks`, `/ttleaderboard`) still fire
  through the client's own hash.
- **Item 2 — "Comfortable rows" is localized in all 11 locales.**
  The code looks the strings up as `HELP_COMFORTABLEROWS_HEADING` and
  `HELP_COMFORTABLEROWS_1` (`Options.lua:404-417` `localizedHelp`, which
  derives `HELP_<KEY>_HEADING` / `HELP_<KEY>_<n>` and falls back PER KEY).
  The same helper feeds the checkbox label (`Options.lua:742`), so the heading
  key covers both. The two keys were added to all eleven files
  (`Locale/<code>.lua`, the two lines sit between `HELP_SHOWSERVERRANK_1` and
  `HELP_SHAMANBLUE_HEADING`, mirroring the `HELP` table order in
  `Options.lua:122-140`). Every value is a real translation; **no English was
  copied into ruRU**.
  NOTE: `enUS.lua` had to gain the keys too — the harness invariant "no locale
  defines a key enUS does not" (`load_test.lua:1903`) would otherwise go red.
- **Item 3 — the `1.2.3` summary row now names the four headline changes.**
  `CHANGELOG.md:7`: the row named only the `GS Rank:` label, the compact class
  icon and the sync transport; it now also names the **Detailed default**, the
  **Shaman Blue** option, the **rebuilt 900px band-stack leaderboard** and the
  **opaque gear panel**.
  **And the gear-panel claim is CORRECTED** (`CHANGELOG.md:71-92`): the old
  text said the panel got "the same dark background and border the leaderboard
  window uses … so the panel reads as one surface with the window behind it".
  That is wrong. The browser window is created with `ButtonFrameTemplate`
  (`RankBrowser.lua:2154`), whose inheritance chain carries NO
  `BackdropTemplateMixin` and therefore no `SetBackdrop`/`SetBackdropColor`
  (VERIFIED on all five branches in `wow-ui-source`: `SharedUIPanelTemplates.xml`
  — classic_era/classic_anniversary `:387`/`:440`/`:545`/`:708`,
  classic_titan `:440`/`:530`/`:532`/`:580`, live `:544`/`:629`/`:631`/`:684`,
  forever `:566`/`:656`/`:658`/`:711`; `grep -c BackdropTemplateMixin` = 0 in
  every one of them). So the window paints its OWN background texture and the
  `if f.SetBackdrop then` at `RankBrowser.lua:2228` never fires; ONLY the gear
  panel carries the 0.9-dark `UI-DialogBox-Background-Dark` backdrop. The
  changelog now says exactly that. No version bump (TOC still `## Version:
  1.2.3`); the `[1.2.2]` and earlier sections are untouched.
- **Item 4 — the unreachable multi-word aliases are documented.**
  `RankBrowser.lua:2812-2831`: a comment above the four multi-word
  registrations states that the client dispatches only the FIRST
  whitespace-delimited token (`ChatFrameEditBox.lua:222`,
  `strmatch(text, "^(/[^%s]+)")`), so `/tt lb`, `/tt rank`, `/tt ranks` and
  `/tt leaderboard` are stored in the client's hash (uppercased, per
  `ChatFrameUtil.lua:724`) but never queried on any of the five clients. The
  registrations are KEPT (harmless) and NO behaviour changed.
- **Pins added to `TacoTip_Extras/Tests/harness/load_test.lua`:**
  - `load_test.lua:7538-7602` — the published global exists, is callable, is
    the SAME function object as `SlashCmdList.TACOTIPRANKS`, opens the
    browser, and survives a model of the client's proxy wipe (a `rawget` of
    the modelled proxy is nil while the global still works).
  - `load_test.lua:1987-2037` — every shipped locale DEFINES both
    "Comfortable rows" keys with a non-empty value, and no translated locale
    carries the English string.
  - `load_test.lua:2321-2343` — applying `ruRU` puts the RUSSIAN heading and
    help text into the merged `TACOEXTRAS_LOCALE` table the options page
    actually reads (end-to-end, not just "the key is in the file").
- **Revert-to-fail (quoted red, on COPIES in `/tmp/opencode`; the working tree
  was never reverted):**
  1. Item 1 reverted → `FAIL TacoTipExtrasToggleLeaderboard is published as a
     callable global` / `FAIL the published global is the same function the
     slash handler invokes` / `FAIL the published global survives the proxy
     wipe` — `577 checks, 3 FAILED`.
  2. Item 2 reverted (keys removed from all 11 files) → `FAIL every shipped
     locale defines the 'Comfortable rows' help keys` — `579 checks, 1 FAILED`.
  3. Item 2 reverted to ENGLISH in ruRU only → `FAIL no translated locale
     carries the English 'Comfortable rows' strings (ruRU included)` /
     `FAIL the merged table carries the Russian 'Comfortable rows' heading` /
     `FAIL the merged table carries the Russian 'Comfortable rows' help text`
     — `582 checks, 3 FAILED`.
- **Current state:** Extras harness `TOTAL 42 invocations: 42 passed, 0 failed`
  (lua5.1 / lua5.4 / luajit, 14 invocations each);
  `cd TacoTip_Extras && luacheck .` → `Total: 0 warnings / 0 errors in 26
  files`; `bash Tools/verify_release_extras.sh` → `verify_release_extras:
  PASS`; the MAIN add-on's harness → `TOTAL 71 invocations: 71 passed, 0
  failed`.
- **Concurrency note:** the main harness went from 70 invocations at this
  desk's baseline to 71 at the end — the other lane added
  `Tests/harness/specname_test.lua`. `main.lua`, the root `CHANGELOG.md`,
  `Tools/verify_release_extras.sh` and `Libs/LibForeverInspector/` were also
  touched by that lane DURING this session (verified by mtime). This desk
  changed none of them.
- **Next step:** the other lane's main-side `/tt` forwarding should call
  `_G.TacoTipExtrasToggleLeaderboard` (the name published here) instead of
  `rawget(SlashCmdList, "TACOTIPRANKS")`. No commit or staging was done.

## 2026-10-20 — [signal:done] Extras side of the four final-review items shipped
- Extras harness 42/42 on lua5.1/lua5.4/luajit; luacheck 0/0 in 26 files;
  `Tools/verify_release_extras.sh` PASS; main harness 71/71 (green, with the
  other lane's `specname_test.lua` in the tree). Every pin reverted to fail on
  a copy first and quoted. No commit, no staging.
