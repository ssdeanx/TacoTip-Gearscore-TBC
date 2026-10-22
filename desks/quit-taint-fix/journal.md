# Quit Taint Fix — Journal

## 2026-10-21 — Desk opened
- **Purpose:** the operator reported, on **Classic Era**, that exiting the game
  is refused: `4x [ADDON_ACTION_FORBIDDEN] AddOn 'TacoTip' tried to call the
  protected function 'UNKNOWN()'` from
  `Blizzard_GameMenu/Shared/GameMenuFrame.lua:69`. `bench/audits/2026-10-20-quit-taint.md`
  (the `quit-taint` desk) had analysed the chain but edited no product file and
  its brief excluded `Libs/` and `TacoTip_Extras`.
- **Scope:** read the client mirror; find the carrier; fix it in the product;
  pin it; validate. Bench artifact:
  `bench/audits/2026-10-21-quit-taint-carrier.md`.
- **Note on the lanes:** two read-only lanes were dispatched. The inventory lane
  had no shell and no mirror access and reported a cross-client claim it could
  not verify — the operator rejected it ("dont use hunter it cant check cross
  client"), and every client claim in the bench artifact was therefore
  re-verified here against `/home/sam/wow-ui-source` with `git show`.

## 2026-10-21 — Step 1: the carrier, verified by hand
- `Libs/LibForeverInspector/LibForeverInspector.lua:5001` replaced the client's
  global `PlaySound` (`Detours:DetourHook` → `LibDetours:134` `rawset(_G, ...)`).
- `origin/classic_era:Interface/AddOns/Blizzard_GameMenu/Shared/GameMenuFrame.lua:66-70`
  — the Logout/Quit closure calls `PlaySound(...)` at `:67` and the protected
  `callback()` at `:69`. **The tainted global is called two lines above the
  refused call, in the same closure.** Verified on all five branches
  (classic_era 67/69, classic_anniversary 67/69, classic_titan 95/97,
  forever 166/168, live 118/120).
- The suppressor installs only when `isClassic` (`:177`, `:4985`) — **Classic Era
  only**, i.e. exactly the operator's client — at file scope (`:5011`).
- This is the carrier the 2026-10-20 audit could not see: its brief named only
  `main.lua` and `options.lua`, and it says so in §7.5.

## 2026-10-21 — Step 2: the fix
- The refusal's sound kit is muted at `GetGameMessageInfo` instead of at
  `PlaySound`. The client reads the sound kit id there
  (`UIErrorsFrame.lua:140-149`) and `GetGameMessageInfo` is called by two
  places in the client, neither of them the game menu. The client's global
  `PlaySound` is now the client's own function again.
- Operator rule applied: **only the inspect-range refusal has its sound
  muted.** A refusal that is not about distance stays audible; the text is
  still swallowed (the 0.8.3 popup fix, unchanged).
- The 2026-10-20 audit's `securecall` recommendation was applied as well:
  every addon callback that enters a Blizzard frame's script chain now runs
  inside `securecall` (main.lua, options.lua, Extras' `boundedCallback`).

## 2026-10-21 — Step 3: the mock was wrong, and that mattered
- `Tests/harness/detect_test.lua` played the refusal's sound from inside its
  `UIErrorsFrame.AddMessage` mock and called `PlaySound` directly. The client
  plays the sound from `TryDisplayMessage`, **after** `AddMessage`, whether or
  not the message was added. The mock now reproduces the client's path —
  otherwise the sound pin could not fail.

## 2026-10-21 — Step 4: pins and revert-to-fail
- New: "the client's global PlaySound is not replaced" (the carrier's
  precondition), "a range refusal with a sound kit plays no sound", "a refusal
  that is not about range keeps its sound", "the client's own sound still
  plays", and three "runs inside securecall" pins in `taint_test.lua`.
- Revert-to-fail proven on a copy at `/tmp/opencode/revert-test`: the
  `PlaySound` detour restored → the carrier pin RED; `runUntainted` unwrapped →
  three containment pins RED.
- `securecall` added to the harness mocks (it is an engine global on all five
  clients; a mock without it exercises the fallback and never the containment).

## 2026-10-21 — [signal:execution/done] exit-game taint fixed
- **Worked on:** found the carrier (a replaced client global `PlaySound`, called
  by the game menu's own Logout/Quit closure two lines above the refused
  protected call), moved the sound interception to `GetGameMessageInfo`,
  applied the operator's range-only sound rule, and contained every addon
  callback that enters a Blizzard frame's script chain with `securecall`.
- **Current state:** `bash Tests/harness/run_all.sh` → **71/71** on lua5.1,
  lua5.4 and luajit; `bash TacoTip_Extras/Tests/harness/run_all.sh` → **42/42**;
  `luacheck .` → **0/0 in 88 files**; `cd TacoTip_Extras && luacheck .` →
  **0/0 in 26 files**; `bash Tools/verify_release.sh --worktree` → **PASS**;
  `bash Tools/verify_release_extras.sh --worktree` → **PASS**.
- **Next step:** the operator reloads on Classic Era and tries to exit the game
  again. If the refusal is gone, the carrier is confirmed. If it is not, the
  next carrier is in `TacoTip_Extras` (not loaded in the reported path) or in
  the `securecall` class itself — the harness cannot settle either, only the
  client can.

## 2026-10-21 — Second pass: per-client verification, and a defect it caught
- **The operator asked for one more pass** before the build ships: every claim
  re-checked **per client**, nothing assumed, nothing already earned broken,
  and **classic_era / classic_anniversary treated as two clients** (and retail /
  forever as two more). The amendment was pushed into the read-only lane that
  was still running, and every load-bearing fact was re-verified here against
  the mirror.
- **A defect in my own fix, caught and fixed.** `TacoTip_Extras/Tooltips.lua`'s
  new `contained()` wrapper closed over `...` inside a non-vararg inner
  function — a compile error in the Lua 5.1 WoW ships. The file failed to
  load and the Extras harness went 36/42 red. Fixed with the same vararg-body
  shape `Frames.lua` uses.
- **Two error-containment gaps closed.** `securecall` swallows a raise, so a
  payload without its own `pcall` fails silently: `options.lua`'s hover
  tooltip and the Extras' `contained()` now report through `safeCall` /
  `noteRenderError` respectively.
- **A load-time `securecall` probe added** (main.lua, options.lua, Extras
  Core.lua): a trivial function is run through it and only a probe that
  actually RAN arms the containment. If any build ever refused addon code to
  call `securecall`, the add-on degrades to the direct call instead of raising
  on every tooltip event, on every client.
- **Per-branch facts now in the bench artifact** (§10.1): the game-menu
  closure lines, `GetGameMessageInfo` call sites (2/2/2/3/2 — and **none** of
  them on a game-menu path on any branch), `securecall` present and captured
  as a local on all five, `xpcall` forwarding extra arguments on all five, the
  shared GameTooltip's script set per branch, `Mixin` never firing on the
  shared tooltip on any client, `GameTooltipStatusBar` absent everywhere, and
  `InspectGuildFrame_Update` existing only on forever/live.
- **Residual items recorded, not changed** (bench artifact §10.5): the Extras'
  options-help hover, the add-on children parented to the shared GameTooltip,
  the per-tooltip `Mixin`, the `InspectGuildFrame_Update` replacement, and the
  `StaticPopupDialogs` key. Each is pre-existing, none is on the game menu's
  path, and each ships in 0.8.4 today.
- **Next step:** unchanged — the operator reloads on Classic Era and tries to
  exit. The per-client table is what the next lane inherits if the refusal
  survives.

## 2026-10-21 — Third pass: the independent sweep landed, and it corrected me
- **The cross-client lane came back and found a real gap in the fix.** The
  tooltip's **status bar IS a live global on every client**: the classic chain
  declares `<StatusBar name="$parentStatusBar" .../>` inside
  `GameTooltipTemplate` (`classic_era:Blizzard_SharedXML/Classic/GameTooltipTemplate.xml:138`),
  the modern chain the same way (`forever`/`live:Blizzard_GameTooltip/Mainline/GameTooltip.xml:9`).
  The `$parent` prefix makes the child's global the parent's name plus the
  child's — the rule this add-on already depends on for `$parentTextLeft1` ->
  `GameTooltipTextLeft1`.
- **I had concluded the opposite** (zero identifier hits on all five branches
  -> "dead code everywhere"). The 2026-10-20 audit's "never runs" claim is
  **withdrawn**: a grep for an identifier is not a proof of absence when the
  XML spells the name differently. The hook is an always-on insertion of addon
  code into a Blizzard frame's script chain -> **now contained**, with a pin
  (revert-to-fail proven: unwrapping `runUntainted` makes four containment pins
  red).
- **A second correction of mine, same shape:** I inferred "the classic
  template inherits `TooltipBackdropTemplate`, so the classic tooltip has
  `SetBackdrop`". It does not — `TooltipBackdropTemplate` is NineSlice-based
  and `SetBackdrop` belongs to `BackdropTemplateMixin`, which no tooltip chain
  mixes in. The add-on's own in-game suite (`Tests/TacoTip_Forever_Tests.lua`
  -> `BackdropTemplateContract`) already records the right client truth, and
  the conclusion (the legacy graft is dead on every client) is unchanged.
- **Confirmed by the sweep:** the replaced-global inventory per branch; **no
  collision between the replaced globals and the game-menu path on any
  branch**; `PlaySound` no longer replaced anywhere; `SlashCmdList` only ever
  written when the client has none (so the client's proxy is never replaced);
  `InspectGuildFrame_Update` exists only on forever/live and is never on the
  game-menu path.
- **State:** 71/71 ×3 interpreters, extras 42/42, luacheck 0/0 (88 and 26
  files), both verifiers PASS.
- **Next step:** unchanged — the operator reloads on Classic Era and tries to
  exit the game. Everything else is now verified per client, and the residual
  items are written down in the bench artifact (§10.5) rather than left in
  someone's head.

## 2026-10-21 — Publish-ready sweep (the house's own gates, checked by hand)
- **The frozen invariants** from `bench/audits/2026-10-20-release-readiness.md`
  §5 were re-read one by one: the range gate (20yd pre-filter, index 1, the
  timings), the gearscore literals, the retail bracket at the shared 1000, the
  wire (`R;2`, 13 fields, 240 bytes), the saved-variable shapes, the
  one-argument `CanInspect` (all four call sites), the translations, the
  deleted whisper path, the TOC bands, and the inspect-frame guild guard.
  **All hold.** Written up in `bench/audits/2026-10-21-publish-gate-verification.md`.
- **Locale hygiene:** 11 locales, identical key sets in both packages, no
  duplicate key, no empty value. One cosmetic finding, NOT changed: the key
  ORDER differs between `enUS` and the other ten — **long-standing** (the same
  drift is at HEAD), no functional effect, and reordering 22 shipped files in
  a publish is churn a release should not carry. Recorded instead.
- **A publish-readiness gap, FIXED:** the release notes come from the README's
  "What's New in 0.8.4", and that section did not mention the exit-game fix.
  It does now, in the README's own voice.
- **The pre-upload test window is UPDATED** with the exit-game test first (and
  the exact text to send if it still refuses), the new `/tacotip diag` line to
  read, a new tooltip-surface block (the containment must change nothing
  visible), and the sound rule stated as expected behaviour.
- **A mock-fidelity finding, FIXED:** the Extras' harness modelled `GetScript`
  as returning the hooked handler and its comment claimed the client chains
  "the original and then the hook" — while the mock returned the hook ALONE.
  The mock now composes them, and the comment states what is VERIFIED about
  the client (Blizzard's own `Blizzard_CombatLog.lua:2867` saves
  `GetScript("OnEvent")` as the original handler) and what is ASSUMED (whether
  a hook chain is included — engine-side). **It cannot affect a player:** the
  shipped add-on never calls `GetScript` on a frame it hooks.
- **RECORDED, not changed:** the in-game WoWUnit suite calls
  `GetScript("OnTooltipSetUnit")` and expects the add-on's hook to run — the
  same assumption — and it **has never been executed** (the 2026-10-18
  test-sufficiency audit says "No execution performed"; no journal mentions a
  `/tttest` run). It is opt-in, not shipped, and not a publish blocker — but
  it is not a passing signal either.
- **The Extras' containment is now pinned** too: the harness counts the calls
  that went through `securecall`, and the pin goes RED when
  `Core.RunUntainted` is unwrapped (proved on a copy).
- **State:** 71/71 ×3 interpreters, extras 42/42, luacheck 0/0 (88 and 26
  files), both verifiers PASS.
- **Next step:** two read-only lanes are still running (an Extras publish
  review and a main-addon publish sweep); their findings land on the bench and
  get reconciled here. The operator's test session can start with the updated
  test window.

## 2026-10-21 — Publish sweep: the Extras lane found a live defect
- **The Extras' Character/Inspect equipment summaries had been DEAD on every
  client, silently.** The Extras hooked `OnSizeChanged` on the paper-doll frame
  with no `HasScript` guard, and the paper doll declares no such script
  (`classic_era:Blizzard_CharacterFrame/Vanilla/PaperDollFrame.xml:127` — it
  declares OnLoad/OnEvent/OnShow/OnHide and nothing else). The client raises
  "bad argument #2 to 'HookScript'" for an undeclared script — the house's own
  record of it, twice — so the raise unwound the whole bind and the equipment
  module never initialized. The leaderboard, the tooltips and the options kept
  working, so only the `/ttgsdebug` ledger showed it.
- **The second fault was the one the MAIN add-on had already fixed in 0.8.4:**
  the summaries were refreshed from the paper doll, whose `OnShow` fired at
  creation (it carries no `hidden` attribute), so the hook could never fire.
  The refresh now comes from the character pane and the inspect pane, which
  are hidden at creation.
- **Every Extras hook now goes through `hookIfDeclared`**, which checks
  `HasScript` first and counts and names every skip and every failure
  (`hookSkipped` / `hookFailed` / `lastHookFailure` in the debug surface).
- **The harness was the reason this hid:** the Extras' mock gave every frame
  every script. The four frames the Extras hooks now carry the client's real
  script sets, and the pins go red on the old code (both proven on copies:
  restoring the unguarded `OnSizeChanged` hook fails the initialization check;
  moving the refresh back onto the paper doll fails the live-trigger check).
- **From the main-sweep lane:** its one valid finding (the visual-clearing
  payloads called two helpers outside any error boundary, so the containment
  path swallowed a raise silently while the fallback propagated it) is FIXED —
  the whole payload now runs inside `safeCall`, so both paths behave the same.
  Its nit about `InspectFrame:OnHide` needs no change (the sweep proved the
  script is declared on all five branches). Its method correction — on the
  classic clients the generated API docs are an incomplete set, so "absent from
  the docs" must never be reported as an absence — is recorded in the bench
  artifact.
- **The operator's test window gained a step:** open the CHARACTER panel and
  look for the Extras' equipment summary, and check that `/ttgsdebug` prints
  `initialize-failures=0`.
- **State:** 71/71 ×3 interpreters, extras 42/42, luacheck 0/0 (88 and 26
  files), both verifiers PASS.

## 2026-10-21 — Correction: the in-game WoWUnit suite is not in use
- **The operator's own statement: the WoWUnit in-game suite is no longer
  used.** So it is not a test surface for this release, and the one caveat I
  raised about it (its `GetScript("OnTooltipSetUnit")` assumption at
  `Tests/TacoTip_Forever_Tests.lua:449`, which nothing pins) is moot — it
  affects a file that never runs.
- **Recorded, not deleted:** the bench artifact says so in §6, and
  `Tests/TacoTipTests.toc` now carries a note that it is not in use and that
  the coverage this release rests on is the OFFLINE harness plus the
  operator's in-game pass. The file is left in the tree because it carries
  uncommitted work against HEAD — deleting it is the operator's call, not a
  side effect of a sweep.
- The coverage that counts: `Tests/harness/run_all.sh` 71 × 3 interpreters,
  `TacoTip_Extras/Tests/harness/run_all.sh` 42, and the operator's own pass
  through `bench/audits/2026-10-20-pre-publish-test-window.md`.

## 2026-10-21 — Final gap pass: one real load-safety defect, one guard reverted

- **Defect found: the tooltip status bar's `OnHide` hook.** No client declares
  `OnHide` on `$parentStatusBar` — the classic chain has `<OnValueChanged>`
  only (`Blizzard_SharedXML/Classic/GameTooltipTemplate.xml:138-148`), the
  modern pair adds `<OnLoad>`/`<OnUpdate>`
  (`Blizzard_GameTooltip/Mainline/GameTooltip.xml:9-23`). `main.lua` hooks it
  at file scope, so on the house's `HookScript` semantics it is the 0.7.8
  failure class. It loads in game, so either the global is nil there or the
  engine tolerates the undeclared script — neither is readable from the mirror.
- **Fixed with a `pcall` (`hookSafely`), not a `HasScript` gate.** A gate would
  skip the hook on all five clients (none declares it) — a behaviour change,
  not a safety measure. The refusal is counted (`statusBarHookRefused`) and
  printed by `/tacotip diag`, so it is not a silent swallow.
- **The suite was blind to it:** `load_test.lua` gave the status bar the
  tooltip's script set. It now declares exactly `{ OnValueChanged = true }`.
  Revert proof: with the guard removed, `load_test CLASSIC_ERA` →
  `main.lua:3837: bad argument #2 to 'HookScript'`, a file-scope abort.
- **A `HasScript` guard on the pane/inspect hooks was tried and REVERTED.** It
  is a no-op in game (`CharacterFrame`/`InspectFrame` declare OnShow/OnHide on
  all five branches, re-verified), but it changes what the 0.7.9
  guildless-inspect pin observes: the pin re-runs `TT:InitInspectFrame` from
  the ADDON_LOADED handler, and it can only do so because the shipped
  `InspectFrame:HookScript("OnHide")` raises on the pin's stub frame and
  short-circuits the lazy-init before it nils the flag. Bisect: guarding
  `OnShow` alone → pin green; guarding `OnHide` alone → pin red (`latch=nil`).
  So those three sites stay as shipped; the reason is written at each site.
- Also corrected the `GetItemLinkByGUID` comment (it is superseded from
  §10.2 of the publish-gate artifact): the API exists on Classic Era; only
  the classic generated docs are thin.
- Gates after the change: 71/71 ×3 interpreters, Extras 42/42, luacheck 0/0 in
  88 and 26 files, both verifiers PASS, and the 0.7.9 pin at ALL 227 PASS.

## 2026-10-21 — The two tooltip bars are different things

- **The health bar under the tooltip is Blizzard's own** `GameTooltipStatusBar`,
  and the add-on keeps it because `show_hp_bar` defaults **true**
  (`options.lua:186`). The add-on only hides it when the player turns that
  option OFF.
- **The power bar is the add-on's own `TacoTipPowerBar`, and `show_power_bar`
  defaults false** (`options.lua:187`) — it is not created at all until the
  checkbox (Options → "Unit tooltip content" → Power Bar) is ticked. The
  operator confirmed 2026-10-21 that it was **never ticked**, so "power bar has
  never shown" is the shipped default, not a regression.
- **This settles the engine question in §10.3 of the publish-gate artifact:**
  the health bar renders, so `GameTooltipStatusBar` exists at render time and
  hooking its undeclared `OnHide` does **not** raise on Classic Era. The
  `pcall` is insurance, not the thing that keeps the add-on loading.
- **Recorded as an evidence gap, not a defect:** the power bar has three
  harness pins (created / updates / colour fallback / re-anchor) and **zero
  in-game observations**. The pre-publish test window gained an OPTIONAL step
  26 so it can be seen once before anything is claimed about it.

## 2026-10-21 — TacoTip Extras final audit (same bar as the main add-on)

Artifact: `bench/audits/2026-10-21-extras-final-audit.md`. Method: per-branch
`origin/<b>` reads of the mirror, by hand; Blizzard's own unguarded call counts
as existence; classic docs treated as incomplete.

- **No load-abort found.** The only file-scope execution is the event frame and
  six `/` aliases. Every `HookScript`/`hooksecurefunc`/`SetScript` is gated and
  pcall'd. Four templates only, all universal. Shipped fonts are the five that
  exist on all five branches.
- **No unguarded client API.** `C_AddOns` exists on all five (125 uses on Era),
  so the primary path runs; `C_AddOns.GetAddOns` is used by Blizzard on none, so
  the Extras probes it and falls back to a global sweep. Item APIs and the
  spec/honor/PvP captures are all `type(...) == "function"` + `pcall`.
- **State is safe.** Absent / pre-1.0.0 / fresh / schema 1 / schema 2 / future
  schema all handled; a future schema is copied, forced to
  `equipmentDisplay = Disabled`, and never written back. Locale parity is
  154 keys × 11 with zero missing and zero code-orphans. Own addon-message
  prefix; never touches the main add-on's `R;2` wire; scoring delegates to
  `TT_GS` through capability probes; `CanInspect` is never called.
- **One open question, not changed blind:** the PvP "modern surface" marker
  (`C_PaperDollInfo.GetInspectRatedBGData`). The mirror cannot settle it — the
  only classic caller is in a `[AllowLoadGameType mists]` file that these
  clients do not load, and the generated docs are not game-type filtered. If it
  exists on Era, the leaderboard's PvP rank/arena are silently empty on the
  classic family. Test-window step 17b is a one-line read-only probe. The
  marker must NOT be removed: Retail/Forever's zeroed PvP fields depend on it.
- **Three test gaps recorded** (no shipped defect): `C_AddOns` absence untested,
  `C_SpecializationInfo`/honor paths unmocked, future-schema DB unseeded. The
  Extras' mock also invents `GameFontHighlightSmallWhite`, which no client has —
  same over-declaration class as the frame-script hole, harmless today.
- Gates unchanged after the audit (docs only): 71/71 ×3, Extras 42/42,
  luacheck 0/0 in 88 and 26 files, both verifiers PASS.

## 2026-10-21 — Extras: the PvP marker switched to client family (operator decision)

- The operator's fact — **"there is no rated bg on classic era"** — exposed that
  the marker was asking the wrong question. `Scanner`/`RankBrowser` decided
  "modern client" from `C_PaperDollInfo.GetInspectRatedBGData`; that is an API
  **stub** test, not a feature test, and a stub on a classic client would zero
  the honor rank and arena fields silently on the whole classic family.
- **Method correction recorded in the artifact:** these branches ship dead
  game-type variants, so "used on branch X" is not "used on the loaded
  client". `GetArenaTeam`'s classic uses are in `Classic/` files gated
  `[tbc, wrath, cata]`; live's `GetPVPRankInfo` uses are in
  `Vanilla/InspectHonorFrame.lua`, gated `[vanilla]`. The mirror therefore
  cannot prove a modern client's API surface by absence.
- **Fix (operator chose identity):** `Core.IsClassicFamilyClient()` reads the
  vendored library's `IsClassic`/`IsTBC`/`IsWotlk`; `Core.UsesModernPvPSurface()`
  composes identity → family, falling back to the old capability probe only
  when identity is unreadable. Scanner and RankBrowser both call it (one
  implementation, two defensive wrappers).
- **Revert-to-fail proof** (API-only marker restored):
  `FAIL classic identity wins over the modern API stub (arena renders)` and
  `FAIL mainline identity hides the synced rating even without the API` — the
  old marker both lost the line on classic and leaked it on mainline.
- `/ttgsdebug` now prints `client-family=… pvp-surface=…`, and test-window step
  17b confirms `classic/classic` on Era. The `[A]` open item is closed.
- Gates: Extras 42/42, luacheck 0/0 in 26 files, main 71/71 ×3, luacheck 0/0 in
  88, both verifiers PASS.

## 2026-10-21 — Custom tooltip position was saved but not applied on world hovers

- Reported: *"something is resetting my tooltip back to bottom corner after i
  save it."* **Nothing was resetting the setting** — it was saved and never
  applied for one class of hover.
- **Cause, from the client:** `GameTooltip_SetDefaultAnchor(GameTooltip, self)`
  runs immediately **before** `GameTooltip:SetUnit(...)`
  (`origin/classic_era:Blizzard_UnitFrame/Classic/UnitFrame.lua`;
  `origin/live:Mainline/UnitFrame.lua:390-391`). The addon's only anchor
  application lived in that post-hook, and its gate asks `tooltip:IsUnit(...)` /
  the display probes — at hook time those describe the **previous** unit. A
  world/mouseover unit therefore read as `"menu"`, the hook returned untouched,
  and the tooltip stayed where the client put it: the bottom-right corner.
  Unit-frame hovers passed through `parent.unit`, which is why it looked
  inconsistent.
- **Fix:** `applyCustomTooltipAnchor(tooltip, unit)` is called at the END of
  `TT:ApplyTooltipAppearance`, which runs **after** `SetUnit` when the unit is
  known. It applies the saved position only when `custom_pos` is a valid
  4-tuple and `anchor_mouse` is off. The post-hook keeps its own paths (mouse
  anchor, two-bar layout, addon-owned frames).
- **Also hardened:** a transient nil `GetLeft()/GetBottom()` on drag stop used to
  overwrite the saved position with the DEFAULT — a silent reset. It now keeps
  what was saved, counts `moverSaveFailed`, and prints the failure.
- **Revert-to-fail proof:** the new call removed →
  `FAIL the tooltip is anchored to the saved position after the unit is known
  handle=true anchored=false point=nil`; the new pin lives in `tooltip_test.lua`
  next to the power-bar pipeline block.
- Gates: 71/71 ×3, Extras 42/42, luacheck 0/0 in 88 and 26 files, both
  verifiers PASS.

## 2026-10-21 — Portrait side measured the client's position, then the save moved it

- Reported: *"in main dir we had it so when portrait went off screen it would
  flip to left side. well its somehow literally pulling it so its literally just
  off screen"* and, after the first fix: *"portrait works when i reload on first
  hover, then stuck offscreen."*
- **Cause, from our own pipeline:** the portrait-side test
  (`tooltip:GetRight() >= screenWidth`) runs *inside* the render, but
  `applyCustomTooltipAnchor` — the fix above — runs at the **end** of it. So the
  decision measured the client's position (classic-era `GameTooltip.lua:109-114`
  anchors `BOTTOMRIGHT` of `UIParent`), chose `"right"`, and the save then moved
  the tooltip to the edge with the portrait outside the screen. The position fix
  moved the goalposts under the side flip.
- **Stuck half:** the side is cached per tooltip and only re-decided on a
  recycle, a scale/invert change, or the first shown render. A wider tooltip on
  the *second* hover therefore kept the first hover's side for the life of the
  `GameTooltip` — the "first hover after reload is fine" half of the report.
- **Fix:** `getPortraitSideRightEdge(tooltip)` answers the edge the tooltip is
  *about to* have — from `custom_anchor` on the handle plus the tooltip's width
  when the saved position owns it, `tooltip:GetRight()` otherwise — and that edge
  is now part of the side-cache key (`portraitRightEdge`, rounded), so a wider
  tooltip re-decides without needing a recycle. Scale/invert/shown rules
  untouched.
- **Revert-to-fail proof:** `getPortraitSideRightEdge` → `tooltip:GetRight()` →
  `FAIL a saved position at the screen edge flips the portrait to the left
  point=TOPLEFT`; the edge key dropped → `FAIL a wider tooltip re-decides the
  portrait side without a recycle point=TOPLEFT`. Both pins are in the new
  "portrait flip must measure the saved position" block in `tooltip_test.lua`.
- Gates: 71/71 ×3, Extras 42/42, luacheck 0/0 in 88 files, both verifiers PASS.

## 2026-10-21 — geometry audit after the flip report ("i think it happened on players too")

- Swept every screen-geometry read on the tooltip path for the same class: a
  decision made from a rect that is not final yet. Inventory and verdicts in
  `bench/audits/2026-10-21-tooltip-geometry-audit.md`.
- **Result:** the portrait side was the ONLY decision in the path that read
  tooltip geometry. Everything else (power bar, status bar, spec icon, border,
  backdrop) only anchors a child to the tooltip and therefore follows it; the
  cursor follower and `anchor_mouse_world` read the cursor by design; drag stop
  reads `GetLeft/GetBottom` only to save, guarded. TacoTip Extras does no tooltip
  geometry reads and no `GameTooltip:SetPoint`.
- **Player variant found:** TacoTip Extras appends its rows AFTER the render, so
  the width measured during the render is the narrow one — the player-side
  version of the same bug. The side decision is now also called from `OnShow`,
  where every line is in and the frame has a rect. Wrap: `runUntainted` (already
  the OnShow hook's wrapper); it mutates only the portrait.
- **Tripwire:** `load_test.lua` reads `main.lua`, slices
  `TT:ApplyTooltipAppearance`, and fails on any `GetRight/GetLeft/GetTop/
  GetBottom/GetWidth/GetHeight` call in it. Revert proof: injecting
  `tooltip:GetRight()` → `FAIL the unit render does not decide from screen
  geometry -- geometry read in the render: :GetRight%(`.
- New pins (all five clients): edge flip, wider-tooltip re-decision, Show-time
  re-decision (`FAIL ... before=TOPLEFT after=TOPLEFT` without the call),
  mouse-mode no-churn (`FAIL ... anchored 5 time(s) across 5 renders` with the
  edge key always on).
- Gates: 71/71 ×3, Extras 42/42, luacheck 0/0 in 88 files, both verifiers PASS.

## 2026-10-21 — [signal:blocked] tooltip still stretches in game; lane terminated

- **Status: NOT fixed, and not claimed.** the operator reports the tooltip still
  stretches, on the second hover, after every change below. the harness is green
  and that proves nothing about the screen.
- **What the tree contains right now (all UNCOMMITTED, none observed in game):**
  saved anchor applied at the end of `TT:ApplyTooltipAppearance`; portrait side
  measured from the anchor target and re-decided on `OnShow` plus a deferred
  guard; a 320px hard width ceiling with word wrap; the guard re-applying the
  cap and arming one bounded follow-up pass. **do not release any of it until
  the operator observes it working.**
- **Evidence that has not been explained away:** the tooltip lines in the
  operator's screenshots — `NpcID`, `Alive`, `Target: None`, `(Hotkey not
  bound)` — appear **nowhere** in this repository (`grep -rn` over the whole
  tree, both add-ons and Libs: no match). so a second add-on is either feeding
  that tooltip or owning it, and the extra width may not be ours to cap at all.
  a width cap here only narrows FontStrings **on `GameTooltip`**; it cannot
  constrain a frame another add-on sizes itself.
- **Unverified hypotheses, in the order they should be checked:** (1) the tooltip
  being rendered is not `GameTooltip`; (2) a second add-on appends after every
  pass and sets its own width; (3) the client's own padding/backdrop layout is
  not recalculated after a late width change (the screenshot shows a wide frame
  with a stale, narrower background — this is what that looks like); (4) the
  second hover simply carries different content and the "stretch" is content,
  not caching.
- **What was verified from the mirror this session** (recorded in
  `workshop.md`, not in a claim): the classic-family `GameTooltip` frame
  declares no `OnShow`; `GameTooltip_SetDefaultAnchor` is byte-identical on
  `classic_era` and `classic_anniversary` and anchors to `UIParent`'s corner;
  the client re-drives a unit tooltip every `TOOLTIP_UPDATE_TIME`;
  `SetWordWrap`/`NewTimer` exist on all five branches; `forever` is
  remotes-only.
- **Process failures recorded in `hands-up.md`:** announcing a green suite as a
  fix; deciding from a predicted rect; four inferred fixes before one
  measurement; a pin that passed while the fix was reverted; a client-coverage
  claim made before checking the operator's own branch.
- Gates at hand-off: main 71/71, Extras 42/42, luacheck 0/0 in 88 files, both
  verifiers PASS. green tree, wrong result — the two are not the same thing.
