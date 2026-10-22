# fix-extras-debug-global — Journal

## 2026-10-20 — Desk opened

- **Purpose:** two items in the TacoTip **Extras** only.
  1. The tree-wide lint warning reported in `TacoTip_Extras/Tests/harness/load_test.lua:4316`
     ("shadowing definition of variable 'core' on line 4173").
  2. Publish the Extras' `/ttgsdebug` snapshot on a plain global — the way
     `RankBrowser.lua` already publishes `_G.TacoTipExtrasToggleLeaderboard` —
     so the main add-on can call it directly instead of reaching into the
     client's slash registry.
- **Scope:** `TacoTip_Extras/Core.lua`, `TacoTip_Extras/Tests/harness/load_test.lua`,
  `TacoTip_Extras/README.md`, `TacoTip_Extras/CHANGELOG.md`.
  **No main file was touched** (the main add-on is being edited concurrently by
  the `fix-main-slash-proxy` lane), no commit, no staging.
- **Baseline measured (not assumed):** `luacheck .` from the repository root →
  `Total: 0 warnings / 0 errors in 88 files`; `cd TacoTip_Extras && luacheck .`
  → `Total: 0 warnings / 0 errors in 26 files`; Extras harness → `TOTAL 42
  invocations: 42 passed, 0 failed`; `Tools/verify_release_extras.sh` → PASS;
  main harness → `TOTAL 71 invocations: 71 passed, 0 failed`.

---

## Item 1 — the reported shadowing warning was ALREADY FIXED in the tree

- **VERIFIED, and the report is stale, not the tree.** The warning in the brief
  does not reproduce. `luacheck .` from the repository root and `luacheck .`
  from inside `TacoTip_Extras` both report **0 warnings / 0 errors** on the
  untouched tree, and the file's inner local is already named `chainCore`, not
  `core` (`TacoTip_Extras/Tests/harness/load_test.lua:4328`):
      4327:    do
      4328:        local chainCore = namespace.Core
  The outer local is `local core = namespace.Core` at `:4185`. **No edit was
  needed and none was made** — the rename the brief asks for is already in the
  tree.
- **Who put it there (evidence, not assumption):** the previous desk's own
  mutation copy, `/tmp/opencode/mut/TacoTip_Extras/Tests/harness/load_test.lua`
  (written 12:52), already contains `chainCore` at `:4328` and `core` at
  `:4185`. Diffing the working tree against that copy shows the file was
  otherwise byte-identical, so the rename landed with the
  `fix-extras-maintainability` pass — before this desk was opened. The brief's
  line numbers (4316 / 4173) are 12 lower than the current file's (4328 /
  4185): the brief was written against a **12-lines-shorter intermediate
  version** of the same file, before the final rename.
- **The diagnosis itself is reproduced, on a COPY, never on the working tree.**
  `/tmp/opencode/shadowproof/` holds a copy of the tree with the inner local
  renamed back to `core`:
      $ cd /tmp/opencode/shadowproof && luacheck . --no-color
      Checking TacoTip_Extras/Tests/harness/load_test.lua 1 warning
          TacoTip_Extras/Tests/harness/load_test.lua:4328:15: shadowing definition of variable 'core' on line 4185
      Total: 1 warning / 0 errors in 26 files
      $ cd /tmp/opencode/shadowproof/TacoTip_Extras && luacheck . --no-color
          Tests/harness/load_test.lua:4328:15: shadowing definition of variable 'core' on line 4185
      Total: 1 warning / 0 errors in 26 files
  So the warning class, the file and the shape in the brief are all real; the
  current tree is already free of it.
- **A CONFIG fact worth recording (it is why the brief saw it in the ROOT
  run).** luacheck loads the **nearest** `.luacheckrc` for each checked file —
  the Extras' own config governs `TacoTip_Extras/**` even when the root
  `luacheck .` walks them, exactly as `TacoTip_Extras/.luacheckrc` says at
  its head ("luacheck loads ONE config per checked file (the nearest
  .luacheckrc, or exactly what --config names)"). The root config's
  `files["TacoTip_Extras/Tests/harness/*.lua"] = { shadowing = false }` block
  (`.luacheckrc:318-324`) therefore **never applies to those files** — the
  Extras' own config leaves shadowing on, so the Extras harness IS checked for
  shadowing in the root run too. Proven by the mutation above: the root run
  reported the warning even though the root config would have suppressed it.
  Not changed here: the root `.luacheckrc` is not this lane's file, and the
  Extras' config is the one that governs.

---

## Item 2 — the debug snapshot is published on a plain global

- **What changed:** `TacoTip_Extras/Core.lua`, inside `registerDebugCommand()`
  (`:1161-1171`) — the function that registers `/ttgsdebug`. The handler is
  published as `_G.TacoTipExtrasPrintDebugSnapshot`, the SAME function object
  the slash entry invokes, via `rawset` (the `RankBrowser.lua:3017` precedent
  for `_G.TacoTipExtrasToggleLeaderboard`; `rawset` also keeps the name out of
  both `.luacheckrc` global lists, so no config file had to change).
- **The slash registration is untouched.** The guard
  (`type(slashList) ~= "table" or slashList.TTEXTRASDEBUG ~= nil`), the
  `_G.SLASH_TTEXTRASDEBUG1 = "/ttgsdebug"` declaration and the
  `slashList.TTEXTRASDEBUG = printDebugSnapshot` assignment are all exactly as
  they were. `/ttgsdebug` still works on its own.
- **The client mechanism, re-verified read-only on all five branches**
  (`/home/sam/wow-ui-source`, `git show origin/<branch>:<path>`):
  - `Blizzard_ChatFrameBase/Shared/ChatFrameSetup.lua` — `:4`
    `setmetatable(list, { __index = {} })`, `:11` `AddListProxyTable(_G.SlashCmdList)`
    — **identical on classic_era, classic_anniversary, classic_titan, forever
    and live**.
  - `Blizzard_ChatFrameBase/Shared/ChatFrameUtil.lua` — `ImportListToHash`:
    `proxyTable[k] = v` at `:732` (the three Classic branches) / `:809`
    (forever, live), then `securecallfunction(tWipe, list)` at `:735` / `:812`.
  - `Blizzard_ChatFrameBase/Shared/ChatFrameEditBox.lua` — the first token only:
    `strmatch(text, "^(/[^%s]+)")` at `:222` (Classic) / `:779` (live); the
    import at `:245` (Classic) / `:253` (forever) / `:247` (live); the dispatch
    at `:257-259` / `:265-267` / `:259-261` — import and dispatch in that
    order, so the real table is already empty when a handler is looked up.
- **A trap found by the harness, not by reading (this changed the shape of the
  fix).** The first attempt published the global on EVERY call to
  `registerDebugCommand`, before the guard. The Extras harness loads a SECOND,
  isolated `Core.lua` instance (`load_test.lua:2800-2804`) and fires its
  `ADDON_LOADED`, so the second instance republished the global with its OWN
  closure while the slash entry — already taken — still pointed at the first
  instance's closure. The identity pin went red:
      FAIL  the published debug global is the same function the slash handler invokes
  The published global is therefore written **once** (only when the name does
  not already hold a function), so the global and the slash entry can never be
  two different objects, whatever the load order. The global is still written
  BEFORE the guard, so it exists even where `SlashCmdList` is not a table yet.
- **The pins added** (`TacoTip_Extras/Tests/harness/load_test.lua:8031-8076`),
  next to the leaderboard's published-global pins:
  1. `TacoTipExtrasPrintDebugSnapshot is published as a callable global`
  2. `the published debug global is the same function the slash handler invokes`
  3. `model: the client's proxy table is empty at dispatch time`
  4. `the published debug global survives the proxy wipe`
  5. `calling the published debug global does not raise`
  6. `the published debug global prints the snapshot`
- **Revert-to-fail, on copies** (`/tmp/opencode/rev-debug/`, the working tree
  was never mutated):
  - **A — the publication removed:**
    `636 checks, 5 FAILED`
    `failed: TacoTipExtrasPrintDebugSnapshot is published as a callable global`
    `failed: the published debug global is the same function the slash handler invokes`
    `failed: the published debug global survives the proxy wipe`
    `failed: calling the published debug global does not raise`
    `failed: the published debug global prints the snapshot`
  - **B — a WRAPPER published instead of the handler itself** (a copy, not the
    same object): `636 checks, 1 FAILED`
    `failed: the published debug global is the same function the slash handler invokes`
    — the identity pin bites on a drifting copy while every other pin stays
    green.
- **What the snapshot prints is unchanged.** The published global IS
  `printDebugSnapshot`; no output line was added, removed or reworded.

---

## Documentation

- `TacoTip_Extras/README.md` — one paragraph in **Usage and settings**: the
  snapshot is published as `_G.TacoTipExtrasPrintDebugSnapshot`, it is the
  same function object the `/ttgsdebug` command invokes, and the printed
  content is unchanged.
- `TacoTip_Extras/CHANGELOG.md` — a new `### The debug snapshot is reachable
  from the main add-on` subsection under the existing `[1.2.3]` section (no
  version bump, no earlier section touched).

---

## Final validation (all commands quoted)

- `bash TacoTip_Extras/Tests/harness/run_all.sh` → `TOTAL 42 invocations: 42 passed, 0 failed`
- `cd TacoTip_Extras && luacheck .` → `Total: 0 warnings / 0 errors in 26 files`
- `luacheck .` (repository root) → `Total: 0 warnings / 0 errors in 88 files`
- `bash Tools/verify_release_extras.sh` → `verify_release_extras: PASS`
- `bash Tests/harness/run_all.sh` (the MAIN add-on) → `TOTAL 71 invocations: 71 passed, 0 failed`
  — green, and **no main file was touched** by this desk.

---

## Notes for the other lane

- The main add-on's `/tt` should call `_G.TacoTipExtrasPrintDebugSnapshot()`
  for the Extras' diagnostic surface. That name is the one published here; the
  main lane's own desk (`fix-main-slash-proxy`) owns the call site. This desk
  did not touch the main add-on.
- A note was left in `desks/fix-main-slash-proxy/journal.md`.
