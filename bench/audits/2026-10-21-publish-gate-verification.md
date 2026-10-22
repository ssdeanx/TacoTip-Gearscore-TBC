# Publish-gate verification — the house's own checklist, checked by hand (2026-10-21)

- **desk:** `quit-taint-fix` (the publish sweep ran inside the fix desk) ·
  **date:** 2026-10-21 · **run_id:** `quittaintfix20261021`
- **kind:** verification of the release gates in
  `bench/audits/2026-10-20-release-readiness.md` §5 (the frozen invariants),
  §6 (packaging) and §7 (the pre-upload test window), plus the publish-sweep
  pass the operator asked for after the taint fix.
- **evidence labels:** VERIFIED / ASSUMED / UNKNOWN, per `CAIRN.md`.
- **method:** read the shipped tree, the harness trees and the client mirror
  (`git -C /home/sam/wow-ui-source show origin/<branch>:<path>`). No web.

---

## 1. The frozen invariants — VERIFIED, one by one

`bench/audits/2026-10-20-release-readiness.md` §5 lists the invariants
"verified at every gate". Each was re-read in the current tree.

| invariant | verdict | evidence |
|---|---|---|
| Era range gate — 20yd pre-filter | **holds** | `LibForeverInspector.lua:484` `local NEARBY_ASK_YARDS = isClassic and 20 or 40` — 20 on Classic Era, 40 on the other four |
| `CheckInteractDistance` index 1 | **holds** | `LibForeverInspector.lua:466` `local INSPECT_INTERACT_DISTANCE_INDEX = 1` |
| distance-first ordering, probe guard, learned ceiling, timings fail-open | **holds** | `INSPECT_DELAY` (`:4039`), `INSPECT_REJECT_COOLDOWN = 10.0` (`:4357`), `INSPECT_GUARD_WINDOW = 0.5` (`:4727`) — none moved |
| the raw GearScore formula literals | **holds** | `gearscore.lua` — the A/B/C tables, `Scale`, `QualityScale`, `ITEM_BAND_SCALE` and every `SlotMOD` are untouched by this fix (the diff touches no gearscore code) |
| Retail bracket at the shared 1000 | **holds** | `gearscore.lua:382` `local BRACKET_SIZE = 1000`; classic → 200 (`:385`), TBC → 400 (`:387`), Forever → 200 (`:389`), unknown → 1000 (`:396`), and **Retail falls through to the shared 1000** |
| wire `R;2` + `G`/`D` | **holds** | `TacoTip_Extras/RankSync.lua:175` `local WIRE_VERSION = "2"`, `:212` `local RECORD_FIELDS = 13`, `:22` `local MAX_PAYLOAD_BYTES = 240` |
| SavedVariables shapes | **holds** | `TacoTip.toc:8` `## SavedVariables: TacoTipConfig`; `TacoTip_Extras/TacoTip_Extras.toc:8` `## SavedVariables: TacoTipExtrasDB` — neither file's schema was touched |
| **no two-argument `CanInspect`** | **holds** | every call site in the shipped tree passes exactly one argument: `LibForeverInspector.lua:5390` `lib:CanInspect("mouseover")`, `:5413` `lib:CanInspect("target")`, `:5469` and `:5482` `lib:CanInspect(u)` |
| no invented translations | **holds** | 11 locales, identical key sets, no key with an empty value (see §2) |
| the Extras whisper path deleted | **holds** | no `SendChatMessage` anywhere in `TacoTip_Extras/`; the only `C_ChatInfo` use is `C_ChatInfo.SendAddonMessage` (`RankSync.lua:95,308`) — the add-on-to-add-on wire, not a whisper |
| TOC versions / interface bands | **holds** | `TacoTip.toc:1-2` `11509, 20506, 38002, 16001, 120105` / `0.8.4`; `TacoTip_Extras.toc:1,6` the same band / `1.2.3` |
| the inspect-frame guild guard stays installed | **holds** | `main.lua:4083-4110` `guardBlizzardInspectGuildFrame()` — untouched, and it only installs on the clients where the global exists (forever, live) |

## 2. Locale hygiene — VERIFIED

Both packages, 11 locales each:

- **identical key sets**: main 239 keys in every locale, 0 missing, 0 extra;
  Extras 154 keys in every locale, 0 missing, 0 extra.
- **no duplicate key** in any of the 22 files — so the key order cannot
  shadow a value.
- **no empty value** in any non-English locale.
- **one cosmetic finding, NOT changed**: the key ORDER differs between `enUS`
  and the other ten (main) and between `enUS` and the other ten (Extras) —
  the same keys, grouped differently. **This is long-standing**: the same
  order drift exists at `HEAD` (verified by reading both revisions), it has no
  functional effect, and reordering 22 shipped files for a cosmetic
  consistency is exactly the kind of churn a publish should not carry. It is
  recorded here instead.

## 3. Packaging — VERIFIED

`bash Tools/verify_release.sh --worktree` → **PASS**; the package is the 27
runtime files (root `*.lua`, `Locale/*.lua`, `Libs/*`, `TacoTip.toc`,
`tt.tga`, README/CHANGELOG/LICENSE/THIRD_PARTY_NOTICES) — no workshop
document, no test file, no lint config, no PNG.
`bash Tools/verify_release_extras.sh --worktree` → **PASS**; the Extras
package is 29 files with all 11 locale files and the `tt-2.tga` icon present.

## 4. A publish-readiness gap that was FIXED — the release notes

The operator's release notes come from the README's "What's New in 0.8.4"
section (`bench/audits/2026-10-20-pre-publish-test-window.md` → "write the
CurseForge release notes from the README's 'What's New in 0.8.4' section").

**That section did not mention the exit-game fix** — and the symptom the
players would have hit is "the game menu's Exit/Log Out does nothing and the
screen fills with `ADDON_ACTION_FORBIDDEN`". The README now carries a
user-facing bullet for it (in the README's own voice, no engineering detail).

## 5. The pre-upload test window — UPDATED

`bench/audits/2026-10-20-pre-publish-test-window.md` now carries:

- **Block A step 0 — the exit-game test, first, with the exact expectation**
  (three clicks: Exit Game, Log Out, Exit Game again) and the exact text to
  send if it still refuses;
- **the new `/tacotip diag` line to read** ("anchor hook failures" must be 0);
- **Block B2 — the tooltip-surface checks** that the containment must not
  change: the guild line, the class colour, the power bar not bleeding
  between hovers, the pane refresh, the mover position;
- **the sound rule, stated as a behaviour the operator should expect**: an
  out-of-range refusal has no sound (muted), a refusal that is **not** about
  the range keeps its sound even though its text stays swallowed;
- a row in the "what to send me" table for a still-refused exit.

## 6. Two mock-fidelity findings — one FIXED, one recorded

**FIXED (Extras harness).** The Extras' harness modelled `GetScript` as
returning the HOOKED handler, and its comment claimed "that is what the real
API does: HookScript chains, so the handler GetScript hands back runs the
original and then the hook" — while the mock returned the hook **alone**,
which is not a chain. The mock now composes them (original, then hook) so it
matches what it claims, and the comment now states what is VERIFIED about the
client and what is ASSUMED:

- **VERIFIED** — `GetScript` returns the handler registered with `SetScript`:
  Blizzard's own code saves it as "the original event handler" and wraps it
  (`origin/classic_era:Interface/AddOns/Blizzard_CombatLog/Classic/Blizzard_CombatLog.lua:2867`
  `local original_OnEvent = COMBATLOG:GetScript("OnEvent");`).
- **ASSUMED** — whether a `HookScript` chain is *also* returned. The engine is
  C++ and the FrameXML mirror cannot settle it.
- **It cannot affect a player**: the shipped add-on never calls `GetScript`
  on a frame it hooks — the CLIENT dispatches its own script chain. The
  uncertainty is about how faithful the harness is, never about behaviour.

**NOT A COVERAGE SURFACE (the in-game suite).** The operator's own statement,
2026-10-21: **the WoWUnit in-game suite is no longer used.** So
`Tests/TacoTip_Forever_Tests.lua` — with its `GetScript("OnTooltipSetUnit")`
assumption at `:449`, which nothing pins — is **not** a test surface for this
release, and no claim of coverage may rest on it. It is excluded from both
packages (both verifiers PASS) and it is left in the tree, not deleted: it
carries uncommitted work against HEAD, and deleting it is a decision for the
operator, not a side effect of a sweep. **The coverage that counts is the
offline harness** — 71 invocations × 3 interpreters for the main add-on and 42
for the Extras — plus the operator's own in-game pass through the pre-publish
test window.

## 7. The containment, re-checked by hand

- **Every call site is a VARARG-forwarding one.** `runUntainted(fn, ...)` is
  the only shape used with a forwarded argument list; the closures that
  capture `tFrame` / `tooltip` / `parent` directly never use `...`. A `...`
  inside a non-vararg function is a Lua 5.1 compile error — the file would
  not load at all — and the main harness loads `main.lua` under lua5.1, so
  this is mechanically proven, not asserted.
- **Every contained payload still reports its own errors.** The tooltip
  handlers through `safeCall`, the anchor post-hook and the panes through
  their own `pcall` + counters, the mover through `safeCall`, the Extras'
  frame callbacks through `boundedCallback`, the Extras' tooltip hooks through
  the `contained()` wrapper's inner `pcall` → `noteRenderError`, and the
  options panel's hover through `safeCall`. `securecall` swallows a raise, so
  a payload without its own `pcall` would fail **silently** — that was the
  gap the pass closed in two places.
- **The load-time probe** means a build that ever refused addon code to call
  `securecall` degrades to the direct call instead of raising on every
  tooltip event. It is load-bearing and pinned: removing it makes the
  containment pins red.
- **No per-event allocation was introduced**: every wrapper is created once,
  at load; the containment adds one C call per event.

## 8. Revert-to-fail proofs, on copies

| revert | result |
|---|---|
| the `PlaySound` global detour restored | the carrier pin RED (`replaced=true`) |
| `main.lua`'s `runUntainted` unwrapped | 4 containment pins RED (`secureCalls=0`) |
| the `securecall` probe not arming the containment | 3 containment pins RED (`secureCalls=0`) |
| the Extras' `Core.RunUntainted` unwrapped | the Extras' containment pin RED (`secureCalls=0`) |

## 9. What this pass could not establish

1. The taint-propagation rule itself — engine-side, **ASSUMED**.
2. Whether `GetScript` returns a hook chain — engine-side, **ASSUMED** (§6),
   and it cannot affect a player.
3. The behaviour of the four clients the operator has never run — every claim
   about them is a claim about the mirror, not about what a player sees.
4. Whether the operator's session had `TacoTip Extras` loaded.

---

## 10. The two publish-sweep lanes — reconciled

Two read-only lanes ran the cross-client sweep with the per-branch discipline:
`bench/audits/2026-10-21-extras-publish-review.md` (the Extras) and
`bench/audits/2026-10-21-main-publish-sweep.md` (the main add-on). Their
findings were re-checked here before anything was changed, and two of them
changed the tree.

### 10.1 The Extras lane found a live defect: the equipment summaries were dead

**VERIFIED by hand, from the client's XML:**

    origin/classic_era:Interface/AddOns/Blizzard_CharacterFrame/Vanilla/PaperDollFrame.xml:127
      <Frame name="PaperDollFrame" setAllPoints="true" enableMouse="true" parent="CharacterFrame" ...>
        -- no <Scripts> of its own; it declares OnLoad / OnEvent / OnShow / OnHide
        -- and NO OnSizeChanged

**The Extras hooked `OnSizeChanged` on that frame with no `HasScript` guard**
(`TacoTip_Extras/Frames.lua`, `bindCharacter` / `bindInspect`). The client
raises "bad argument #2 to 'HookScript'" for a script the frame does not
declare — the house's own record of it twice: the 0.7.8 changelog ("an
unguarded HookScript raised at file scope on Retail, which aborted the
remainder of main.lua") and `main.lua:2918-2929`. The raise unwound the whole
bind, `Frames.Initialize` was caught by `Core.lua`'s `guarded(...)`, and **the
equipment module never initialized on any client** — silently, because the
leaderboard, the tooltips and the options all kept working and the only trace
was one line in the `/ttgsdebug` initialization ledger.

**A second fault, the same one the main add-on had already fixed in 0.8.4:**
the summaries were refreshed from the **paper doll**, which carries no
`hidden` attribute and is therefore shown from the moment the client creates
it — its `OnShow` fired long before the add-on loaded, so a hook on it could
never fire again.

**Fixed:**
- every hook in the Extras is now installed through `hookIfDeclared`, which
  checks `HasScript` first and **counts and names** every skip and failure
  (`Frames.GetDebugState()` → `hookSkipped`, `hookFailed`, `lastHookFailure`);
- the character context is refreshed from the **character pane** and the
  inspect context from the **inspect pane** — both hidden at creation, so
  their `OnShow` fires once per open (the main add-on's 0.8.4 pattern,
  `main.lua:3916`).

**And the harness was corrected, because it was the reason this hid:** the
Extras' mock gave **every frame every script**, so it could not see an
unguarded hook on a frame that declares no such script. The four frames the
Extras hooks now carry the client's real script sets. The pins go red on the
old code: restoring the unguarded `OnSizeChanged` hook fails the
initialization check, and moving the refresh back onto the paper doll fails
the live-trigger check. Both proven on copies.

### 10.2 The main-sweep lane's findings

| finding | verdict |
|---|---|
| the `OnTooltipCleared` / `OnHide` containment payloads called `isUnitFramePeriodicUpdate` and `cancelDelayedTooltip` outside any error boundary, so the containment path swallowed a raise silently while the fallback propagated it | **VALID — FIXED.** The whole payload now runs inside `safeCall`, so both paths behave identically (caught and reported) |
| `InspectFrame:HookScript("OnHide", …)` has no existence guard on `InspectFrame` | **NIT — not changed.** The main add-on's own `InspectFrame:OnShow` hook guards the same global, and the sweep proved the script is declared on all five branches; changing it would add a branch the sweep shows is not needed |
| the `GetItemLinkByGUID` comment says the API is "documented only on Forever and Retail" | **NIT — the comment is wrong** (the API exists on Classic Era; Blizzard calls it unguarded at `origin/classic_era:…/Blizzard_SharedXMLGame/Tooltip/TooltipUtil.lua:14`). The behaviour is conservative and unchanged. Recorded, not changed — a comment fix inside a hot path is churn this release should not carry |
| the locale key ORDER differs between `enUS` and the other ten | **matches §2 — long-standing, cosmetic, not changed** |
| `options.lua` adds a saved-variable key (`scan = true`) since the last commit | additive and default-safe (0.8.4 work, not this sweep) |
| `LibDataBroker-1.1/` and `LibDBIcon-1.0/` are untracked folders in the working tree | they are **not in the archive** the verifiers check (both PASS) and not in the toc. **Upload the archive, not the folder** — a folder zip would carry them |
| the provenance of 8 same-spelling non-English values | **UNKNOWN** and unverifiable here (the mirror carries english-only FrameXML). The values are words that are correct in those languages. Not a defect, not claimed as one |
| the classic branches' generated API docs are an incomplete set (`CreateFrame`, `UnitRace`, `GetBuildInfo`, `C_Item.GetItemLinkByGUID` are absent from them and present in the client's tree) | a **method** correction, recorded here: on the classic clients, "absent from the generated API docs" must never be reported as an absence |

**The sweep's B2 answer — which hook sites can raise, per branch — is "none, on
any of the five clients"**, with the client's own `HookScript` on
undeclared-but-default scripts as the proof. That is the cross-client answer
the main add-on needed, and it is why the main add-on's hook sites are safe
where the Extras' were not.

### 10.3 The final gap pass — one real load-safety defect, and two corrections

**Two entries in §10.2 are superseded here:** the `GetItemLinkByGUID` comment
is now corrected (it was "recorded, not changed"), and the `InspectFrame:OnHide`
nit was examined, guarded, and deliberately **reverted** — the reason is below.

**The defect: the tooltip status bar's `OnHide` hook.**
Every client's tooltip status bar declares **no `OnHide`**:

| branch | the `$parentStatusBar` script set |
| :--- | :--- |
| classic_era / classic_anniversary / classic_titan | `<OnValueChanged>` only — `Blizzard_SharedXML/Classic/GameTooltipTemplate.xml:138-148` |
| forever / live | `<OnLoad>`, `<OnUpdate>`, `<OnValueChanged>` — `Blizzard_GameTooltip/Mainline/GameTooltip.xml:9-23` |

`main.lua` hooks `OnHide` on it at **file scope** (`stage("status-bar")`), so
under the house's recorded `HookScript` semantics that is the 0.7.8 failure
class — an abort of the **rest of `main.lua`**. That the add-on loads in game
means either the global is nil at that point or the engine tolerates the
undeclared script; neither is readable from the mirror, and both readings are
now safe.

**Why the suite never saw it:** `Tests/harness/load_test.lua` handed the status
bar the **tooltip's** script set, so the raise could not fire. Corrected: the
status bar now declares exactly `{ OnValueChanged = true }` — the intersection
of the five branches, and the honest set. Over-declaring is what hid the
defect.

**The fix is a `pcall` (`hookSafely`), not a `HasScript` gate.** Because no
client declares `OnHide`, a gate would skip the hook on **all five** — a
behaviour change, not a safety measure. The `pcall` installs it exactly where
the client accepts it (today's behaviour on the only client observed in game)
and turns a refusal into a counted skip, surfaced by `/tacotip diag` as
`tooltip status-bar hook refused`.

**Revert-to-fail proof** (guard removed, faithful mock):

    LOAD FAIL  family=classicEra   main.lua: ./main.lua:3837: bad argument #2 to 'HookScript'

**The guard that was tried and reverted, on purpose.** Guarding the character
pane and inspect pane hooks with `HasScript` is a **no-op in game** —
`CharacterFrame` and `InspectFrame` declare `OnShow`/`OnHide` on all five
branches (re-verified this pass on classic_era Vanilla and live Mainline). But
it changes what the **0.7.9 guildless-inspect pin** observes: that pin re-runs
`TT:InitInspectFrame` from the `ADDON_LOADED` handler, and it can only do so
because the shipped `InspectFrame:HookScript("OnHide")` **raises on the pin's
stub frame** (a bare table with no `HookScript`) and short-circuits the
lazy-init in `TT:RefreshInspectFrame` before it can nil the flag. Guarded, the
init completes, the flag disappears, and the pin goes red (`latch=nil`).
Bisect: guarding `OnShow` alone leaves the pin green; guarding `OnHide` alone
turns it red. So those three sites stay exactly as shipped in 0.7.9/0.8.3,
with the reason written at each site so a later lane does not re-break the pin
while "hardening" it.

**The engine question is SETTLED — by the operator's own observation
(2026-10-21).** The tooltip's health status bar renders in game, so
`GameTooltipStatusBar` exists at render time and `HookScript("OnHide")` on its
undeclared script does **not** raise on Classic Era. The `pcall` is therefore
insurance rather than the thing that keeps the add-on loading — insurance that
costs nothing and covers the four clients nobody has observed.

**And the power bar has never been seen because it is off by default.**
`show_power_bar = false` (`options.lua:187`) against `show_hp_bar = true`
(`:186`): the health bar under the tooltip is Blizzard's own, and the add-on's
power bar was never created on the operator's install. That is the shipped
default, not a defect — but it also means the teardown hook above guards a bar
that has never existed in any observed session, and that the feature has three
harness pins and **zero in-game observations**. The test window gained an
OPTIONAL step so it can be seen once before anything is claimed about it.

**The `GetItemLinkByGUID` comment** now records that the API is documented only
on Forever/Retail because the classic branches' generated docs are an
incomplete set, that Blizzard calls it unguarded on Classic Era
(`origin/classic_era:…/Blizzard_SharedXMLGame/Tooltip/TooltipUtil.lua:14`), and
that the guard is the **runtime probe**, not the documentation.
