# Changelog — TacoTip

All notable changes to TacoTip are documented in this file.

| Version | Date | Summary |
| :--- | :--- | :--- |
| `0.8.3` | `2026-10-14` | **Fixes the "Not in Range" error popup, and stops treating an inspect range the game never told us about as if it were known.** `NotifyInspect` is a server request, and a refused inspect reaches the player as the client's own UI error — red text plus the spoken error. The FrameXML mirror shows that sink (`UIErrorsFrame` consuming `UI_ERROR_MESSAGE`) and does **not** show which call produces it, so the fix covers both candidates rather than guessing, and on Classic Era the refusal is swallowed inside a short window around the addon's own probes and used to learn that client's real range. Every refused hover used to put the message up — reported on Classic Era 1.15.9, TBC Anniversary and Retail as happening "every Time you drive with mouse over Players" — and on Classic Era it repeats for as long as a far unit stays targeted. The request is wrapped in `pcall`, a refused player is remembered for 10s (one mouse sweep previously cost one request per player *per mouse move*), and each range refusal tightens a per-family ceiling so the client discovers its own real inspect range at runtime instead of relying on a hardcoded radius. Also adds a **proximity scan** with a nameplate fallback for `mouseover` / `target` / `focus`, a 3s watchdog so a lost `INSPECT_READY` cannot deadlock the queue, `GetTime()` (monotonic uptime) for cache stamps instead of wall clock, and inspect telemetry in `/tacotip diag`. **Plus the follow-up that stops the repeat spam:** the range ceiling was never actually learnable, because distance was read from `UnitDistance` — which is documented on none of the five clients — so the whole discovery mechanism was unreachable code and a target that walked out of range was re-asked every 10 seconds indefinitely. `UnitDistanceSquared` is now read and a range refusal marks the unit out of range until the live distance signal says otherwise. **Classic Era was also being misclassified**, which is why the popup was Classic-only in practice: `isClassic` required `clientBuildMajor == 1`, but Classic Era's `GetBuildInfo()` slot 4 is `nil` and slot 7 carries the build, so it resolved to `6` and Classic Era was routed into the *mainline* "either signal is enough" branch. Identity now comes from `WOW_PROJECT_ID` alone. **Also fixed: the portrait was hidden and re-anchored on every Classic render where unit resolution failed, and never restored** — the Classic script hook drops its varargs, so the GUID fallback is structurally unreachable on that family. Full detail, including two wrong turns recorded rather than quietly edited away, in the sections below. |
| `0.8.2` | `2026-10-13` | **Typography, portrait sizing, and a portrait-side control.** The tooltip name line is rendered 2pt larger than body text (it was previously flattened to the body size, which is why the name read as just another row). Portrait base reduced from `72x96` to `66x88` — still an exact 3:4 ratio and still exact integers at every slider stop (`33x44`, `66x88`, `99x132`, `132x176`). New **Invert portrait side** option (default off) to pin the 3D/2D portrait to either side of the tooltip; the side cache is keyed on the flag so the change applies on the very next render. Localization extended to 263 keys across all 11 locales. | **Inspect regression fixes.** Classic Era / SoD / TBC Anniversary / Titanforge again require `CheckInteractDistance(unit, 1)` in addition to `CanInspect` (CanInspect is range-agnostic there, so 0.8.1 fired `NotifyInspect` at out-of-range players and stalled the queue); Retail/Forever keep the either-signal rule unchanged. `UNIT_INVENTORY_CHANGED` now flags a cache entry `stale` instead of zeroing its timestamp, so GearScore/iLvl no longer vanish from the tooltip while a re-inspect is pending (or if it cannot run). TacoTip Extras' remote-result cache freshness raised from 10s to 300s (the library's refresh window) so Extras rows no longer disappear seconds after appearing. | **Inspect regression fixes.** Classic Era / SoD / TBC Anniversary / Titanforge again require `CheckInteractDistance(unit, 1)` in addition to `CanInspect` (CanInspect is range-agnostic there, so 0.8.1 fired `NotifyInspect` at out-of-range players and stalled the queue); Retail/Forever keep the either-signal rule unchanged. `UNIT_INVENTORY_CHANGED` now flags a cache entry `stale` instead of zeroing its timestamp, so GearScore/iLvl no longer vanish from the tooltip while a re-inspect is pending (or if it cannot run). TacoTip Extras' remote-result cache freshness raised from 10s to 300s (the library's refresh window) so Extras rows no longer disappear seconds after appearing.
| `0.8.1` | `2026-10-12` | **Inspection engine performance, proactive pre-caching, and range responsiveness.** Pre-caches player gear/talents immediately on target selection (`PLAYER_TARGET_CHANGED`) and 3D world mouseover (`UPDATE_MOUSEOVER_UNIT`). Triggers dynamic inspection on group roster updates (`GROUP_ROSTER_UPDATE`) and gear swaps (`UNIT_INVENTORY_CHANGED`). Accelerates queue processing with a 0.5s ticker, an adaptive 0.8s throttle on Retail/Forever, and instant next-inspect dispatch upon `INSPECT_READY`. Prioritizes actively targeted players. Fixes max-range inspect dead zones by accepting either `CanInspect` or `CheckInteractDistance`. Resolves inspect frame "Scanning equipment..." deadlock by firing full `INVENTORY_READY` parameters `(guid, true, unit)`, binding `InspectFrame.unit` fallback tokens, and handling remote uncached item IDs. |
| `0.8.0` | `2026-10-11` | **GearScore correctness — the first release whose suite asserts a GearScore *value*.** Corrects two-handed weapon weighting so standalone 2H weapons retain their full 2.0x weight (`SlotMOD = 2.0`, balancing with 1H+Shield wielders), while strictly applying the `0.5` dampening factor to Titan's Grip dual-wielding where an offhand item is equipped alongside a 2H weapon. Hardens asynchronous item loading against uncached nil returns, standardizes Hunter weapon scaling, and accurately maps item quality colour bands via `ITEM_BAND_SCALE`. |
| `0.7.9` | `2026-10-10` | **Corrects the 3D portrait on Retail and WoW Forever, and gives the tooltip border a per-client default.** The portrait strobed only on the modern pair because the modern client fires the tooltip post-calls *before* its own `Show()`, so the whole unit handler ran against a frame that had never been laid out — which turned two cosmetic defects into the visible bug. **Re-verified 2026-10-10:** stationary unit-frame hover periodic destroy/reset fixed on Retail, right-click inspect gear stripping on Retail/Forever resolved, force-inspect on hover eliminated, guildless inspect crash protected, another addon adding a tooltip line erased by line-clear fixed, redundant-parameter IDE diagnostic resolved, all 11 locales at 100% parity, and the harness passing with 51/51 tests. Also: `/tt diag` gained event counters and a silent-failure report that no Lua error handler can produce. |
| `0.7.8` | `2026-09-29` | **First cross-engine release, and the one that replaces the Classic-only addon.** Runs unchanged on all five client families — Classic Era / SoD, TBC Anniversary, WotLK Titanforge, WoW Forever and Retail. Rebuilt client detection, completed the localization registry, and corrected the WoW Forever GearScore bracket. Fixed the two defects that left Retail and WoW Forever running **half** the addon: an unguarded `HookScript("OnTooltipSetUnit", ...)` that raised at file scope because Retail's tooltip template does not declare that script, and `CreateFrame("Texture", ...)`, which is not a valid frame type, followed by `SetFrameLevel` on that texture — a `Frame` method that does not exist on a modern `Region`. Fixed the tooltip being loaded twice, the addon not loading on Titanforge, and stock Blizzard tooltips on TBC Anniversary and Titanforge. Fixed the tooltip backdrop mixin being grafted onto modern tooltips. Fixed the 3D portrait being destroyed and reloaded roughly twice a second while hovering a unit frame, and a stray specialization icon appearing on the wrong character. Resolved the Pawn scale library per client instead of guessing it, which had been spamming *ScaleName must be the name of an existing scale* on every character tooltip — the one defect `pcall` could not mask, because Pawn reports it by writing to the chat frame. Added `/tacotip diag` and an offline verification harness (50 invocations across all five clients). |
| `0.7.7` | `2026-09-21` | **Initial Universal Cross-Engine Release**: Complete 1:1 architectural port enabling TacoTip to run concurrently on WoW Forever (`16001`), Retail Live (`110002`–`120100`), WotLK Classic & Titanforge (`38001`), TBC Classic Anniversary (`20506`), and Classic Era / Season of Discovery (`11509`). Powered by `LibForeverInspector` with multi-client engine gating, adaptive quality brackets, universal Settings & ColorPicker API bridges, and zero-allocation tooltip pipeline. |

---

## [0.8.3] — 2026-10-14

### Localization

- **FIX — the unit `Level` label was hardcoded English on every client.** `main.lua` built the line as `"|cFFFFFFFFLevel|r %s"` while `["Level"]` is translated in all 11 locale files. Every *other* unit-tooltip label (`Target`, `Guild`, `Rank`, `Talents`, `Pet`, `Realm`, `Item Level`…) already resolved through `TACOTIP_LOCALE`, so this was the single label bypassing the locale system — it read `Level` in Korean, Russian and Chinese too. Now resolves via `L["Level"]` with an `or "Level"` fallback so the line stays safe even if a future locale omits the key before the merge can backfill it. Revert-to-fail proven on **all five clients**; the test had to be moved out of the modern post-call block first, because that block is `if (usePipeline and POSTCALLS and #POSTCALLS >= 2)` and Classic never enters it — the test as first written covered only 2 of 5 clients and the mutation exposed it immediately.
- **Removed 24 unreferenced keys from all 11 locale files (263 → 239).** Every one was verified dead first: absent from every `L["..."]` lookup in the addon, absent from `TacoTip_Extras`, and absent from the stale root addon copy (which carries its own self-contained `Locale/` and is unaffected). They were superseded pre-`OPTIONS_*` option labels (`Show GearScore in character frame`, `Unit Tooltips`, `Lock Position`, `Mover`…), plus `Undead`, `Extra`, `RANK_TITLE`, `REALM` and a malformed `" the Kingslayer"` with a leading space. **One was deliberately kept:** `"enUS"` is not a display string at all — it is `_G.TACOTIP_LOCALES["enUS"] = defaults`, the registry entry that locale selection depends on, and deleting it would break every locale. `Average iLvl` was also removable here because `TacoTip_Extras/Frames.lua:449` passes it as a *literal* to `metricRow()` rather than reading TacoTip's locale table; it becomes a proper key in Extras' own locale work.
- **`load_test` now asserts every `L["Key"]` lookup actually resolves**, replacing `nlocale >= 251`. That magic number was only ever a proxy for "the locale table is wired": it went red when the 24 dead keys were pruned even though nothing was broken, and it would have stayed green if a *referenced* key were deleted as long as enough others remained. Scanning the addon sources and requiring every lookup to be non-`nil` in `_G.TACOTIP_LOCALE` tracks the real invariant and needs no updating when keys are added or removed. Two traps it has to handle, both found by making it wrong first: keys containing `\n` are a two-character escape in source but a **real newline** once loaded (24 correctly-defined keys reported as missing until the scan unescaped before comparing), and several keys are legitimately **numeric** — `["CHARACTER_FRAME_GS_TITLE_FONT_SIZE"] = 10`, the `*_XPOS` / `*_YPOS` frame offsets — so the check must test for `nil`, not `type(...) ~= "string"`. A shell-quoted `grep` was tried first and silently returned zero matches, which would have made the assertion a no-op that passes for the wrong reason; it reads the files in plain Lua instead. Verified: 239 lookups / 239 defined / 0 unresolved.
- **Documentation corrected:** `.omg/memory/localization_system.md` described the fallback as a `setmetatable` `__index`, but the real implementation in `_G.TacoTipApplyLocale()` is a **copy-merge** that fills `_G.TACOTIP_LOCALE` in place. That distinction has two consequences now written down: main.lua's file-scope `local L = _G.TACOTIP_LOCALE` stays valid across a locale switch, and — because it is a copy, not a metatable — a key added to a locale file *after* a switch has already run will not retroactively update the merged table.

### Inspect

- **FIX — the "walk out of range and it errors over and over" report** (Classic Era; the same code path covers all five clients, which is why it was chased rather than patched locally). Target a player, walk out of range, and the addon kept re-asking the server for that player until you untargeted them. Four independent causes, each individually sufficient to keep the noise going:
  1. **The library measured distance with an API that does not exist on any supported client.** `inspectDistance()` read `_G.UnitDistance`, which appears in the generated API documentation of **none** of `classic_era`, `classic_anniversary`, `classic_titan`, `forever` or `live` (verified in the wow-ui-source checkout; the documented function is `UnitDistanceSquared(unit) -> distance, checkedDistance`). The helper therefore returned `nil` forever, which made `exceedsLearnedRange()` permanently false and `lib.inspectRangeLimit` permanently empty — **the runtime range-discovery described in the entry below was unreachable code**, and everything it was meant to prevent still happened, just 10 seconds later instead of immediately. `UnitDistanceSquared` is now read first, `UnitDistance` kept as a fallback, its `checkedDistance` flag honoured (a `false` there means the number is not trustworthy and is treated as absent, not as "very close"), and comparisons done on **squares** — the learned limit is the squared distance the client refused at, so `sqrt`-then-compare would round and could accept a unit the client just rejected.
  2. **The rejection memory was a timer, not a state.** `isInspectCoolingDown()` released a refused unit after `INSPECT_REJECT_COOLDOWN` (10s) whether or not it had come back. A target that stayed out of range therefore cost one server error every 10 seconds, forever — the "over and over" in the report. A range refusal now also sets `lib.inspectOutOfRange[guid]`, which is **not** cleared by the clock: it is lifted only when the live distance signal says the unit is reachable again (measurably closer than it was at the refusal, *and* `CheckInteractDistance` agreeing). Walking back in range still inspects on the very next tick, so there is no lasting penalty for having been far away. Only a rejection whose message says *range* sets this — "Cannot Inspect", dead, ghosted or shielded are different problems and keep the plain 10s cooldown.
  3. **Blizzard's own range gate was not being used.** All five branches of `Blizzard_InspectUI` gate this exact call with `if (CanInspect(unit, true)) then NotifyInspect(unit) end` — vanilla, TBC, wrath, camelot and mainline are line-for-line identical — and the second argument is the range flag. `requestInspect()` now calls `CanInspect(unit, true)` and refuses before the request when it answers false. It is applied **at the single point `NotifyInspect` is actually called** rather than inside `lib:CanInspect`, because the harness pins `lib:CanInspect`'s mainline "either signal is enough" contract on all five clients and tightening that method would break real coverage. The gate is strictly additional: a client that ignores the second argument is unaffected, because passing it can only make the decision stricter, never looser.
     > ⚠️ **This item is WRONG and is superseded below, in the same release.** The second argument is `showError`, not a range flag — passing it makes the engine *display* a message, so this item made the very popup it was written to prevent, and `CanInspect` never tested distance. It is not corrected in place here so the wrong turn stays readable in the history rather than being quietly edited away. See *"`CanInspect`'s second argument is `showError`, not a range gate"* below for the evidence, the reversal, and the three tests that had to be inverted because they asserted this item's contract.
  4. **The hot paths now refuse far units before doing any work.** `isCloseEnoughToAsk()` (~28 yards, matching the range class of interaction index 1) short-circuits the inspect queue tick (target, queue, party, up to 40 raid members) and the proximity scan, so a far-away target costs one `UnitDistanceSquared` call instead of the whole `CanInspect` chain — the tick runs twice a second, and a selected out-of-range target sits in it until it is untargeted. An unmeasurable unit returns "near", so this can only ever remove work; it can never approve a request `lib:CanInspect` would have refused.
- **Telemetry** gained `scanSkippedDistance` on the pre-filter path, alongside the existing refusal / learned-range counters, so "is it still asking?" is answerable from `/tacotip diag`.

### `CanInspect`'s second argument is `showError`, not a range gate — WRONG TURN, and not yet proven to be the cause

- **The wrong turn, recorded because the code that made it is still in the tree above and in the comment that justified it.** Item 3 under *Inspect* adds `CanInspect(unit, true)` to `requestInspect()` on the belief — stated in the old comment as settled fact — that the second argument is a range flag. It is not. Its documented meaning is *"Flag — If true, the function will display an error message ('You can't inspect that unit') if you cannot inspect the specified unit. **This function doesn't check whether you're close enough to the unit to inspect it; use `CheckInteractDistance` for that.**"* That is two independent statements in one entry, and they invert the change: passing `true` makes the **engine display an error**, and `CanInspect` never tested distance in the first place. So the call site added to suppress an "out of range" popup was itself a source of one — when the gate refused, the popup had already been raised, and the code then went on to read that refusal as distance evidence, which the same documentation says it is not.
- **Where the meaning comes from, stated precisely because the first draft of this entry got it wrong.** The `showError` meaning is documented in **two external API references** — [warcraft.wiki.gg](https://warcraft.wiki.gg/wiki/API_CanInspect) and [the WowWiki archive](https://wowwiki-archive.fandom.com/wiki/API_CanInspect) — in identical wording. It is **not** in the local FrameXML mirror: the generated API documentation lists `CanInspect` with a **single** argument on every branch and says nothing about a second, so it cannot be cited as the source. What the mirror *does* supply is weaker, structural corroboration: Blizzard's own call sites use **two different forms for two different purposes** — `Blizzard_UnitPopupShared/UnitPopupSharedButtonMixins.lua` calls the **one**-argument form (`CanInspect(contextData.unit)`) to decide whether to enable a popup button, while `Blizzard_InspectUI/*/Blizzard_InspectUI.lua` calls the **two**-argument form (`CanInspect(unit, true)`) from `InspectFrame_Show`. A range flag would have one form and be passed everywhere; two forms differing exactly on the "tell the player" axis is `showError`. `InspectFrame_Show` is reached only from explicit user action (`/inspect`, right-click → Inspect), where a message is the intended outcome. A library asking on the player's behalf, in response to a cursor sweep, must not request one. That structure is what makes `showError` the better reading; it is not what establishes it, and this entry should not pretend otherwise.
- **What the old reasoning actually rested on.** The comment read the generated docs' single-argument `CanInspect(unit)` listing as evidence, and concluded *"the published Classic Era CanInspect signature takes the unit only … so the range flag above cannot be the whole gate there"*. That is not a deduction. The docs list one argument while Blizzard's own code passes two, so the listing is an arity gap in the `FunctionParameters` block, not evidence the flag is absent. A grep of the local FrameXML mirror showed Blizzard *calling* the two-argument form, and a call site proves a name is used — it says nothing about what an argument means. The meaning had to come from the API entry, and reading it invalidates the change. Per `AGENTS.md`: *do not infer an API surface from a loose grep*; this one was inferred from a grep and shipped.
- **What changed.** `requestInspect()` now calls `CanInspect(unit)` — the unit token alone. `CanInspect` remains the unit-validity check it actually is (`lib:CanInspect` already used the one-argument form and needed no change). The distance gate on this family is `CheckInteractDistance(unit, 1)` — index 1 is the inspect interaction range — which is applied at the single point `NotifyInspect` is called and again in `lib:CanInspect`. The old comment block, which asserted the opposite in five places, is replaced with the reasoning above.
- **NOT CONFIRMED to be the cause of the player's popup.** This removes a call that was demonstrably asking the engine to display a message; it does not establish that the popup a player reported came from this call. Attribution is still open, and the counters cannot answer it: `notifies` / `rejected` / `lastError` are cumulative since `/reload`, so a player who loads and stands away from everyone reports them all as zero — which reads identically whether no inspect was attempted or whether one was attempted and something else raised the message. Those two have opposite fixes, so a bounded capture is added to separate them (below) and the diag print is to be written once the numbers come back.
- **Three of this suite's own tests asserted the wrong contract and had to be inverted**, which is the same failure one release later and one layer down:
  1. `<client> range: CanInspect(unit,true) false blocks the request` asserted that a `showError` refusal **suppresses** the request. It now asserts the opposite and is **stronger**: when the engine would refuse-and-display, the request must still go out, because the library must never ask the question that displays anything. Its mock was also corrected — it was `function(unit, dist) if (dist ~= nil) then return rangeAllowed end return true end`, branching on arity, which is a mock of the wrong contract rather than of the API.
  2. `<client> range: back in range, the unit is inspected again` moved its unit from 3yd to **2yd**. Step 3 no longer blocks the request, so it now issues a real one, and a real refusal at 3yd teaches the learned ceiling 3. Asserting recovery at 3yd would have been asserting that the out-of-range memory never engages.
  3. The event-path mock `CanInspect = function(u, rangeFlag) if (rangeFlag ~= nil) then return not far end return true end` has a now-dead second branch. Left in place; it is harmless and keeping it avoids churn, but it is dead.
- **Every new assertion is revert-to-fail proven**, on all five clients. The stub is arity-sensitive (`select("#", ...)` recorded per call), which no earlier `CanInspect` mock in this file was — they are all `function() return true end`, which answers identically to one argument and to two. That is precisely why the two-argument call shipped with a green suite.
  1. *Re-introducing `CanInspect(unit, true)`* → `CanInspect is called with EXACTLY one argument` fails on all five clients (`calls=3 maxArity=2`) **and** `CanInspect's showError refusal does NOT block the request` fails on all five (`requests=0`). The second is the corrected pre-existing test biting for the same reason, which is the point of keeping it.
  2. *Disabling `installNotifyCapture`* → `a notify entry is recorded` fails on all five (`entries=0`).
  3. *Disabling `installUIErrorFilter`* → five assertions fail on all five clients: the filter is not installed (`event=nil`), the return-nothing check has no filter to call (`n=-1`), no error entry (`type=nil msg=nil`), the ring buffer is not bounded by the 60 driven messages (`entries=1`), and the filter is not removable (`removed=nil`).
  - `luacheck` stayed clean. The new block initially introduced two warnings (`clock` shadowing the preceding inspect block, and a `filters` table mutated but never read). The local is renamed and the dead table dropped; `LibForeverInspector.lua` is at 0 warnings and `detect_test.lua` is back to its one pre-existing `table.unpack` warning.

### Temporary attribution capture — REMOVED in the same unreleased release

> ⚠️ **The scaffolding described in this section no longer exists in the code, and it is kept here only as the record of what was tried.** The origin is **not** settled — see *Classic Era: the out-of-range message* below for exactly what the mirror does and does not show — so `lib.errorLog`, the `NotifyInspect` wrapper, the `ChatFrame_AddMessageEventFilter` install, the `UIErrorsFrame` capture frame, `lib.inspectLastNotified*` and the `/tacotip diag` attribution section were all deleted. The reason it never answered the question on its own is worth keeping: it could only *observe* the popup. The one hook it installed that could have suppressed anything was a `hooksecurefunc`, which by construction cannot change a call — which is why the operator saw "nothing changes" while the counters climbed.

- **`lib.errorLog`** — a 50-entry ring buffer of plain tables, overwritten oldest-out-first, so it cannot grow without bound across a long session. Two entry kinds:
  - `kind = "notify"` — `_G.NotifyInspect` was actually invoked, recording the unit token, its GUID, `GetTime()`, the measured distance from the existing `inspectDistance()`, and the live answers of `CheckInteractDistance(unit, 1)` and `CanInspect(unit)` (one argument, deliberately). Captured by installing a transparent pass-through wrapper over `_G.NotifyInspect` at library load, so it records invocations from **every** caller and not only this library's own. The original is kept on `lib.originalNotifyInspect`.
  - `kind = "error"` — a `UI_ERROR_MESSAGE` filter fired, recording the `messageType`, the string resolved through `GetGameMessageInfo` when it exists, and `GetTime()`.
- **The filter returns nothing.** A `ChatFrame_AddMessageEventFilter` that returned `false` would suppress the message — which destroys the evidence it was installed to collect, and would look like a fix.
- **Accessors:** `lib:GetErrorLog()` (oldest-first; returns a copy once the ring has wrapped, so a caller printing it cannot reorder the live buffer), `lib:ClearErrorLog()`, and `lib:RemoveErrorFilter()` to detach the filter in a live session.
- **`/tacotip diag` now prints it** — a `-- inspect error attribution (temporary) --` section showing the last 15 entries, one per line, with a clock delta relative to the previous entry so "did an error follow a request?" is answerable at a glance. Read-only and guarded on both `CI.GetErrorLog` existing and the call itself being `pcall`'d. A `notify` line prints its unit token, measured distance, `interactDistance` and `canInspect`; an `error` line prints its `messageType` and the message resolved through `GetGameMessageInfo`. The reading that answers the open question is a `notify` with `distance` in the 20–28yd band while `interactDistance` is `true` — that proves the `NEARBY_ASK_YARDS` pre-filter sits below the server's real refusal point and can be raised.
- **This scaffolding is temporary and is named as such in both the code and the diag output.** It exists to attribute a popup that is *not yet attributed*; it is not a feature and should be removed once the origin is settled.
- **Guarded to the same standard as everything else on this path:** both installs are `type(...) == "function"` checked and `pcall`'d, because neither `NotifyInspect` nor `ChatFrame_AddMessageEventFilter` is guaranteed to exist, and an unguarded raise at file scope takes the whole library down — the failure `TT.LOAD_STAGE` exists to name. Entry construction is inside one `pcall` each, so a hostile return from a distance API cannot take the inspect call down with it.

### "Out of Range" is a real engine error, throttled on Retail and deliberately NOT throttled on the Classic clients

- **`LE_GAME_ERR_OUT_OF_RANGE` is a genuine engine error constant**, delivered on `UI_ERROR_MESSAGE` and resolved through `GetGameMessageInfo` for the sound. The red-text-plus-sound popup is that path. ⚠️ **The rest of this bullet was wrong; it is kept here and corrected in full under *Classic Era: the out-of-range message, its mechanism, and the fix* below.** It read: *"It is a **server** response: `LE_GAME_ERR_*` is a C-side enum an addon cannot fabricate, so the popup is proof that something sent a request the server refused — which is why the fix is about *not sending the request*, not about suppressing the message."* A C-side enum being unfabricatable does **not** make it server-driven: the client's own C code raises these too. Which of the two inspect calls produces it on Classic Era is still **ASSUMED**, not proven — see the corrected section below — but gating only the *request* demonstrably changed nothing, which is what five releases of failed fixes looked like from the operator's side.

- **The per-client asymmetry that explains "it only happens on Classic Era":**

  | branch | `Blizzard_UIErrorsFrame/…/UIErrorsFrame.lua` | throttled? |
  | :--- | :--- | :--- |
  | `classic_era` | line 90 | **no** — `--[LE_GAME_ERR_OUT_OF_RANGE] = true,` |
  | `classic_anniversary` | line 90 | **no** — same, commented |
  | `classic_titan` | line 90 | **no** — same, commented |
  | `live` (Retail) | line 92 | **yes** — live entry |

  On all three Classic clients the throttle entry is **commented out**, so every occurrence fires a full popup with no de-duplication. On Retail it is active and repeats collapse. Same server behaviour, different noise — so "it works on Retail" is **not** evidence the code path differs. This is the concrete reason the report is Classic-only; it is not a different inspect rule.

- **`pcall` never suppressed this class of popup.** `UI_ERROR_MESSAGE` travels into `UIErrorsFrame`, a different frame from the call stack, so wrapping `NotifyInspect` cannot stop it. Blizzard's own suppression is an **event registration** (`Blizzard_ChatFrameBase/Shared/SlashCommands.lua` unregisters and re-registers `UI_ERROR_MESSAGE`), not an error handler. Any earlier wording in this file that credits `pcall`, or a per-unit cooldown, with stopping *the error* is overstating it: those reduce request **volume**, which is a real and separate win, not popup suppression.

- **No inspect-specific `LE_GAME_ERR_*` exists in FrameXML** — the enumerable names are all spell / resource / ability errors. Do **not** read that as proof none exists: only constants FrameXML references appear in a grep, and this enum is C-side. Absence in the mirror is not evidence of absence, and repeating that mistake in the other direction would be its own kind of wrong.

### Classic Era: the out-of-range message — what is known, what is not, and what changed

**Read this section as evidence-labelled, not as a claim that the popup's origin is proven.** Four independent mirror-only audits were run against this change before it was trusted; what follows is the corrected record, including the parts the earlier draft of this section asserted without evidence.

**What the mirror shows (all quotes branch-qualified; the three classic branches are byte-identical for these files).**

- **The sink.** `Blizzard_UIErrorsFrame/Classic/UIErrorsFrame.xml:3` declares the global frame `UIErrorsFrame` with `mixin="UIErrorsMixin"`, loaded on all three classic branches by `Blizzard_UIErrorsFrame_Classic.toc`. `Classic/UIErrorsFrame.lua:140` displays a UI error with `self:AddMessage(message, r, g, b, 1.0, messageType)` — the id is the last argument, formally `messageID` (`SimpleMessageFrameAPIDocumentation.lua:9-24`) — and `:142-146` resolves it with `GetGameMessageInfo(messageType)` and plays `C_Sound.PlayVocalErrorSound(voiceID)` or `PlaySound(soundKitID)`. The same file's other two `AddMessage` calls pass only five arguments (`:14` SYSMSG, `:154` external/system), which is what makes the two paths distinguishable.
- **The name convention.** `GetGameMessageInfo` returns `errorName` (cstring, non-nilable), `soundKitID`, `voiceID` (`GameErrorDocumentation.lua:10-29`), and Blizzard's own code proves the first return is a *global-string name*: `Blizzard_Channels/VoiceUtils.lua:82-84` does `local stringId = GetGameMessageInfo(gameError); … _G[stringId]`.
- **Blizzard's own inspect procedure, on every branch: `CanInspect(unit, true)` then `NotifyInspect(unit)`, with no range check anywhere** (`Blizzard_InspectUI/Vanilla/…:3-10` and `TBC/…:8-17` on the classic branches; `Camelot/…:41-49`; `Mainline/…:8-17`). `CanInspect` is documented with a single argument on all five branches; the second argument's meaning is not documented anywhere in the mirror. `CheckInteractDistance` is called at exactly one site per branch (`UnitPopupSharedUtils.lua:194`), only for buttons that declare a distance, and never with a literal index — the values in use are `0,1,2,3,4,5`, where **index 1 is the achievement-comparison button** (`Wrath/UnitPopupButtons.lua:265-266`, `Standard/…:5-7`), not an inspect range. The inspect button inherits `nil` and is exempt.
- **No inspect yardage exists in the mirror at all.** The only yardage constant in FrameXML is `DISTANCE_THRESHOLD_SQUARED = 250*250` for compact unit frames; `CheckInteractDistance` is documented with names and types only. The one distance pattern Blizzard itself uses is `local distance, checkedDistance = UnitDistanceSquared(unit); if checkedDistance then … end` (`CompactUnitFrame.lua:1069-1074`) — the shape this library already had.

**What the repo shows.** The pre-port library this project replaced gated distance first and asked the query second (`OLD/Libs/LibClassicInspector/LibClassicInspector.lua:3422-3423`), and armed its suppression on the one-argument query form (`:3329-3337`), swallowing `ERR_UNIT_NOT_FOUND` / `ERR_INVALID_INSPECT_TARGET` / `ERR_OUT_OF_RANGE` and `PlayVocalErrorSoundID(10)` (`:3339-3365`). It also did **not** auto-inspect on `PLAYER_TARGET_CHANGED` or `UPDATE_MOUSEOVER_UNIT`; those triggers are new in the port.

**What is NOT known — and this is why the fix is built the way it is.**

- **No producer for an inspect refusal appears anywhere in the mirror.** Nothing in any Lua on any branch says that a refused `CanInspect` or a refused `NotifyInspect` raises `UI_ERROR_MESSAGE`; the mirror shows the sink, not who writes to it. The earlier draft of this section asserted the query as the cause; that remains **ASSUMED**, not verified.
- **Whether the refusal is delivered synchronously inside the call or by event dispatch afterwards is also not in the mirror.** The evidence leans to event dispatch — `UIErrorsFrame` consumes `UI_ERROR_MESSAGE` through `OnEvent`, and Blizzard's own suppression of these messages is event-level (`Blizzard_ChatFrameBase/Shared/SlashCommands.lua:1305-1310` unregisters the event), which is only coherent if the event is the path — but it is not proven for this message.
- **The three `ERR_*` globals appear nowhere in the mirror, and no GlobalStrings file exists on any branch.** Any design that matched on `_G.ERR_*` or required `_G[name] == message` would therefore be relying on something unverifiable. The guard does not: it matches the `errorName` that `GetGameMessageInfo` returns.

**The fix, as it now stands.**

1. **Order, on Classic Era, in both paths.** `lib:CanInspect` and `requestInspectImpl` now read the distance signal before the query, so a unit the cheap gate rejects is never asked about. This restores the pre-port order on that family. The other four clients keep the order they shipped with.
2. **A window-based probe guard (Classic Era only).** Every engine call to the inspect surface goes through one of three probes, each of which arms a short attribution window (0.5s) when it returns; an outstanding request keeps its own window. The sink — a `LibDetours` detour on `UIErrorsFrame:AddMessage` and on the sound APIs — swallows an inspect refusal that arrives **either** synchronously inside our call **or** by event dispatch inside a window, so the fix does not depend on the unanswered sync-vs-async question. It never swallows a message that lacks a `messageID` (a SYSMSG), never swallows while `InspectFrame` is shown (the player's own `/inspect`), and treats "this client resolved no name" as attributable *because the window is only open around our own call*.
3. **Classification before learning.** Only `ERR_OUT_OF_RANGE` tightens the learned ceiling and marks the unit out of range. The other two names — and any unresolved name — get the per-unit cooldown and teach **nothing**; passing the unit's distance there would have set a ceiling at wherever the unit happened to stand, so a non-range refusal at 5yd would have blocked every unit at 5yd and beyond for the rest of the session.
4. **The comments that the mirror contradicts are corrected**, including the two worst: "index 1 is used by NO button on any branch" (it is the achievement button's gate on Wrath and Retail) and "`CheckInteractDistance(unit, 1)` is what Blizzard's own unit-popup buttons and its inspect flow consult" (the popup consults it only for buttons that declare a distance; the inspect flow consults `CanInspect` alone). The "~28 yard" figure and the claim that `NotifyInspect` answers as a Lua error raised inside the call are also gone — neither is in the mirror.

**Per client — one changes, and the other four change in exactly one respect.**

| client | project constant | guard installed | gate order | behaviour change |
| :--- | :--- | :--- | :--- | :--- |
| Classic Era | `WOW_PROJECT_CLASSIC` (2) | yes | distance-first | the refusal is swallowed, recorded, and (if it is a range refusal) learned from |
| TBC Anniversary | `WOW_PROJECT_BURNING_CRUSADE_CLASSIC` (5) | no | query-first (unchanged) | none beyond raise-safety |
| WotLK Titanforge | `WOW_PROJECT_WRATH_CLASSIC` (11) | no | query-first (unchanged) | none beyond raise-safety |
| WoW Forever | `WOW_PROJECT_MAINLINE` (1), interface 16000–19999 | no | either-signal (unchanged) | none beyond raise-safety |
| Retail | `WOW_PROJECT_MAINLINE` (1), interface ≥ 20000 | no | either-signal (unchanged) | none beyond raise-safety |

**"None beyond raise-safety" is precise, and the earlier draft's "none" was not.** Every engine call on this path is now wrapped in a `pcall` by the probe helpers, so a call that *raises* reads as "no answer" instead of aborting the handler it ran inside. Same calls, same arguments, same order, same accept/reject rule on those four clients — but a raising client is handled differently, and that difference is real.

**Verification.** `bash Tests/harness/run_all.sh` — read the counts from its output. `detect_test` runs under lua5.1, lua5.4 and luajit. The guard's tests drive a mock client that refuses the way the report describes and, critically, emit the message **after** the call has returned (the async shape the mirror suggests), plus: the refusal is swallowed and recorded; a non-range refusal is swallowed but teaches no range; the ceiling still tightens for a range refusal; only the sound the client actually plays is armed, and a message carrying both ids arms only the voice; an unrelated sound and an unrelated error still play and display; the install retries when `UIErrorsFrame` appears late; the player's own inspect message displays while the frame is up; and a message this client cannot name is still swallowed inside the window. **Six mutations, each reverted:** window not armed → the async assertion fails; non-range refusals allowed to teach → the classification assertion fails; both sound latches armed → the both-ids assertion fails; install retry removed → the retry assertion fails; the `InspectFrame` guard removed → the player assertion fails; requiring a name → the unnamed assertion fails.

### Performance / range thresholds

- **Client-family range thresholds:** Classic Era uses `20` yards for out-of-range recheck and nearby-ask cutoff; larger-variant clients use `40` yards.
- ⚠️ **Those two numbers do not match the range they were introduced to match, and the mismatch was documented as if it did.** The `NEARBY_ASK_YARDS` comment claimed it "matches the ~28 yard inspect range"; `20 ≠ 28` and `40 ≠ 28`, so neither branch did. What it actually is: a conservative pre-filter, **stricter** than the `CheckInteractDistance(unit, 1)` gate it protects on Classic and looser on the others. The Classic strictness has a real cost — a player at 20–28yd is inspectable and will **not** be inspected, because the pre-filter refuses before `lib:CanInspect` is consulted. That is a missed-inspect cost, not an error cost: it cannot produce an out-of-range popup, only absent data. **The value is not changed in this release**; it should be set from observed client behaviour, and the client now measures itself: every refused probe tightens `lib.inspectRangeLimit[family]`, which `/tacotip diag` prints as `learned max range`. That number — not an assumption — is what this pre-filter should be set from next: raised where the client allows more, never lowered below the learned limit.
- **`INSPECT_INTERACT_DISTANCE_INDEX = 1` is an inference, not a verification**, and the comment claiming otherwise has been corrected. Read off the real call sites the enum is 0 = guild/team ops, 2 = trade, 3 = duel, 4 = follow, 5 = pet-battle duel, with the base mixin and the inspect button both returning `nil` (which is why `UnitPopupSharedUtil.IsEnabled` skips the distance check for inspect entirely). Index 1 is used by **no** button on **any** branch, so "1 = inspect" is by elimination. Reasonable, externally corroborated, and still unproven — the runtime value is what `CheckInteractDistance` actually returns.
- **The `UnitDistance` fallback in `inspectDistance` is unreachable on all five clients.** That name appears in the generated API documentation of none of `classic_era`, `classic_anniversary`, `classic_titan`, `forever`, `live`; only `UnitDistanceSquared` does. Every apparent hit for the plain form is a substring of `UnitDistanceSquared` or `UnitDistanceCheckUpdate`. Retained defensively only; do not reason about behaviour as though it can execute.
- **GearScore item-data collects:** `RequestLoadItemDataByID` calls are now globally throttled to once per item ID per `2.0s`, preventing repeated item-data collect spam during rapid tooltip refreshes.

### Inspect engine — what 0.8.3 actually delivered

These are the product fixes, not test corrections. (They were misfiled under a "green for the wrong reason" heading for a while; the split is cosmetic and the content is unchanged.)

- **The request is wrapped in `pcall`.** ⚠️ **This bullet originally said "This is the fix that ends the popup". That was wrong.** `pcall` never saw this class of popup — `UI_ERROR_MESSAGE` travels into `UIErrorsFrame`, a different frame from the call stack — and the branch it guards never ran on the client that reported the symptom, because the refusal is not a Lua error there. The wrapper is kept because a raise from `NotifyInspect` must never abort the inspect path, and because it is now where the request is attributed to its unit; it is not what silences anything.
- **A refused unit is remembered for 10s.** One rejection is enough evidence. Previously a single mouse sweep issued one request per player *per mouse move*, which is exactly how the report reads: "every Time you drive with mouse over Players".
- **The refusal teaches the client its real range.** The tightest distance the client has refused becomes this client's ceiling and is never exceeded again. This is deliberately *runtime discovery* rather than a hardcoded radius: the API docs on disk (Classic Era 1.15.9) document `CanInspect` as a bool that says nothing about distance, and `NotifyInspect` documents no error behaviour at all — so there is no documented way to ask "is this unit in inspect range". Reporting showed two users disagreeing on the trigger distance (5 metres vs 40 yards), which is consistent with a gate that does not mean what it was assumed to mean.
- **Removed the range-bypassing hysteresis added earlier in this release.** It let a recently-inspected unit through a *failed* distance check — so a player who walked out of range was still requested, and raised the exact error it was meant to prevent. Boundary flicker now costs a skipped inspect instead of an error popup. The test that covered it asserted the wrong contract and is now inverted.
- **Nameplate fallback.** The proximity scan falls back to `mouseover` / `target` / `focus` when no nameplate resolves to a player, so the feature still works with friendly nameplates off (the default, and the case where the nameplate pass alone does nothing). It is keyed on *no plate resolved*, not on *nothing was enqueued* — a plate that resolved but was cached or out of range means nameplates are working, and falling through on top of that would add a server request to every tick.
- **Proximity world scan:** `LibForeverInspector` enumerates visible nameplates on a throttled ticker, distance-gates each unit via `CheckInteractDistance` (per-family rule), and enqueues in-range players so GearScore is collected without hovering each player. Budget + backoff guard hitching; disabled in combat. Per-plate fault isolation prevents a single bad nameplate from aborting the tick.
- **Range robustness:** centralized `INSPECT_INTERACT_DISTANCE_INDEX`; 3-second watchdog releases stalled inspect slots so the queue cannot deadlock.
- **Cache timestamps now come from `GetTime()` (uptime), not `time()` (wall clock).** `time` was used as a bare global and was only ever supplied by the test harness, never by production code. Uptime is monotonic, so an NTP correction or timezone change can no longer make the 300s freshness window read as expired or not-yet-valid, and it resets exactly when the in-memory cache does. The clock read is guarded, because it sits on the inspect pipeline: an unguarded raise in `isCacheFresh` or in `cacheUnitData` would abort `INSPECT_READY` *before* the callbacks fire — a tooltip that silently never populates, with nothing logged anywhere.
- **Telemetry:** `GetInspectStats()` (notify / ready / timeout / refusals recorded / probe errors suppressed / error speech suppressed / error sound suppressed / learned max range / scan-enqueued / scan-via-fallback / scan-skipped) plus `SetScanEnabled()`, surfaced in `/tacotip diag`. The refusal counters are how a player reports whether they are still hitting this: a rising count while sweeping means the client enforces a tighter range than the gate APIs advertise. `lastError` is labelled **last inspect-call error** because it is only set when the engine *call* raises — it is not the refusal, and the old label read as "no refusals" while `probe errors suppressed` climbed beside it.

### Classic Era was misclassified — and fixing that broke the event path it was protecting

- **`isClassic` never matched the real Classic Era client.** It required `clientBuildMajor == 1`, but Classic Era's `GetBuildInfo()` puts `nil` in slot 4 and the build number in slot 7, so `clientBuildMajor` resolved to `6`. Classic Era was therefore routed into the **mainline** "either signal is enough" `CanInspect` branch, which is the one policy that lets an out-of-range unit reach `NotifyInspect`. This is the mechanical reason the reported popup was Classic-only. Fixed by identifying Classic Era from `WOW_PROJECT_ID` alone — the signal that is actually distinct per Classic client (`LibForeverInspector.lua:140`).
- **The event paths bypassed the ask range.** `PLAYER_TARGET_CHANGED`, `UPDATE_MOUSEOVER_UNIT`, `UNIT_INVENTORY_CHANGED` and the tooltip-show path in `main.lua` now all pass through `isCloseEnoughToAsk`, so they cannot reach `NotifyInspect` around the per-client ask gate.
- **`inspectOutOfRange` no longer lifts on "still inside 20yd".** It stores the distance at refusal time and lifts only when the unit has measurably moved **closer** than it was at the refusal — or was unmeasurable and became measurable — while still lifting instantly when `CheckInteractDistance` flips false→true. The old rule lifted a refused unit sitting at 15yd immediately, so it re-asked and re-errored once per cooldown: the reported spam.
- **⚠️ And that edit broke the event path it was protecting.** `isCloseEnoughToAsk` was referenced from the `OnEvent` handler while being declared further down the file. A Lua local is only in scope **from its declaration onward**, so every player target and every player hover raised `attempt to call global 'isCloseEnoughToAsk' (a nil value)` — red text at the top of the screen, on exactly the two triggers in the report — and the handler aborted before it could inspect anything. It is now forward-declared at `:3714` and assigned at `:4419`. This is the release's second wrong turn and it is recorded here rather than edited away, because a fix that introduces a louder bug than the one it removes is worth reading twice.
- **`NotifyInspect` re-checks `CheckInteractDistance(unit, 1)` for the Classic family at the single point it is actually called.** That call, *not* `CanInspect`, is the range gate on those clients. (The earlier reasoning for also adding a second `CanInspect` argument was itself wrong — see the `showError` section above.)
- **The dead fixed-yardage recheck constant is removed.** It referenced the same never-learned ceiling the `UnitDistance` bug had already made unreachable.
- **`detect_test` now fires the real `PLAYER_TARGET_CHANGED` / `UPDATE_MOUSEOVER_UNIT` handler.** The suite had always *claimed* to drive these paths and never did — which is how a nil-global raise on every player hover shipped green.
- **`/tacotip diag` no longer raises a false alarm on the Classic family.** The unknown-client check flagged anything that was "neither Retail nor WoW Forever", which is true *by design* for Classic Era, TBC Anniversary and Titanforge — so a perfectly healthy Classic Era client opened a red **PROBLEMS** section. It now flags only `CI:IsUnknown()`, a family that resolved to nothing. `load_test` asserts the false alarm stays gone, revert-to-fail proven.

### Portrait lifecycle — the Classic destroy/hide/re-anchor

- **The portrait was hidden, re-anchored, and never restored on the Classic family.** `onTooltipSetUnit` resolves its unit in three steps: `tooltip:GetUnit()`, then `resolveTooltipUnit`, then — only if both fail — `resolveUnitTokenFromGUID(data.guid)`. That third step is the safety net for exactly the case where `GetUnit()` fails. It is **structurally unreachable on Classic**, because the `OnTooltipSetUnit` script hook is registered as `function(tooltip, ...) handleTooltipSetUnit(tooltip) end` and drops its varargs, so `data` is `nil` on every Classic render. Retail and WoW Forever get a real `data` from `TooltipDataProcessor.AddTooltipPostCall` and never hit the branch at all.
- **Consequences, all Classic-only:** `incomingGUID` was always `nil`, so `keepModel` was always `false`; that made the unresolved branch hide the portrait *and* reset `portraitSide` / `portraitAnchored` (the re-anchor) *every* render; and the branch then `return`ed, skipping `ApplyTooltipAppearance`, which holds the only `portrait:Show()` in the file. **Nothing re-showed it.** Worst case a portrait that stayed gone for the rest of that tooltip show.
- **The fix passes `keepModel = not changeUnproven`** (`main.lua:1586-1597`), where `changeUnproven` means *there is no guid, or it matches what is already rendered* — i.e. nothing has been shown to have changed. On Classic that is now always true, so the hide and the anchor-epoch reset are both skipped entirely. A guid that is present **and different** is a real unit change and still tears down correctly. A guarded `portrait:Show()` restore sits behind it as a belt-and-braces for a portrait hidden by some other route.
- **Classic-specificity is proven, not asserted.** Removing the fix turns the new assertion *an unresolvable render does NOT leave the 3D portrait hidden* red on **Classic Era, TBC Anniversary and Titanforge only** — Forever and Retail stay green, because they take the guid-compare keep path and never reach the defect.
- **`Hide()` had no counter that could see it, and the two tests named for this bug were therefore blind to it.** `TT.ev.portraitHide` sits *inside* `if (not retainModel)`, so it counts **teardowns, not `Hide()` calls**. Lifting `Hide()` out of its guard — exactly the shape of this bug — left both pre-existing tests green on all five clients. That gap is now closed by `TT.ev.portraitModelHidden`, incremented on **every** hide, and the reproduction is recorded in the revert-to-fail table below.
- **`/tacotip diag` counters were relabelled to match what they count.** `portrait hide` counted teardowns and said otherwise; it is now `portrait teardowns (hide + ClearModel)`, with a separate `portrait Hide() calls (on clear)` and `portrait destroys (ClearModel)`. The trailing guidance — "portrait destroy should be ~1 for a character and 0 for a re-hover of the same one" — was wrong for anything but the first unit after a `/reload`, and now says so.
- **13 new assertions, running on all five clients through each client's real delivery path** (Classic script hook / modern post-call), covering: a same-unit re-render does not hide the portrait, a real recycle (`OnTooltipCleared` / `OnHide`) does, and the unresolved render leaves it visible. One precondition was written, found to **pass for the wrong reason** (non-wide `tip_style` rewrites lines via `SetText` instead of appending, so a resolved render also adds zero lines), and corrected in the *test* rather than the code — with the reason left in the comment.
- **⚠️ Still outstanding, on every client:** `getTooltipState(tooltip).currentUnitGUID` is **never cleared**. The guid-change teardown therefore fires on the first render of any unit after a `/reload` regardless of who it is, and again on every A→B→A sequence. On Retail that means re-hovering a character already seen this session still destroys and rebuilds the mesh. Diagnosable from the new counters; **not fixed in this release.**

### Harness corrections — the range gate and `CanInspect`

- **A test asserted the old broken contract and had to be inverted.** `a refused player is asked exactly once while sweeping` expected `mouseover` (at 40yd) to be requested **once** and refused. It was only ever true because the library never measured distance, so a player 40 yards away — outside inspect range — was asked anyway. With distance actually measured the correct assertion is **zero** requests for a unit outside inspect range, which is stronger than "one request and a refusal". The neighbouring `after the cooldown, a unit beyond the learned limit is still refused` was inverted the same way (`mouseoverAfter == 1` → `== 0`), and its "both refusals happened — 40yd and 6yd" comment corrected: only one refusal can happen now, because only one unit is ever asked.
- **Three revert-to-fail probes, each of which initially passed for the wrong reason** — which is the entire reason the probes exist:
  1. *The `CanInspect(unit, true)` probe passed with the gate deleted*, because the test's mock returned `false` for **both** `CanInspect(unit)` and `CanInspect(unit, true)`, and `lib:CanInspect`'s pre-existing `CanInspect(unit)` call was already rejecting it. The mock now returns `true` without the flag and only `rangeAllowed` with it — the real Classic-era contract — and deleting the gate now turns `CanInspect(unit,true) false blocks the request` red on all five clients.
  2. *The pre-filter probe passed with `UnitDistanceSquared` unreadable*, because the out-of-range scenario was simultaneously protected by the learned-range limit, so removing either defence alone changed nothing observable. The tests are now split by what can save them: the distance-measurable block exercises the pre-filter and the range flag, and a separate **no-distance block** (no `UnitDistance` and no `UnitDistanceSquared` at all — what every client actually shipped before this fix) exercises the state-based memory alone. Deleting the state memory in that block reproduces the reported bug exactly: **60 requests against the same out-of-range target over 600 seconds**.
  3. *The in-range test asserted two requests for two entry points*, which failed once the request throttle worked as intended. The hover render and the proximity scan run inside the same inspect window, so the second is deliberately coalesced; the assertion now expects the single request that is the real contract.
- **New coverage, all five clients, both entry points** (the tooltip hook that calls `DoInspect`, and the proximity scan fallback that owns `target` in `SCAN_FALLBACK_UNITS`): in-range target is inspected exactly once; out-of-range hover makes no request; out-of-range scan makes no request; a clock 600 seconds past every cooldown does not revive the request; `CanInspect(unit, true)` false blocks the request; back in range, the unit is inspected again. Plus the no-distance block above, and the recovery case asserted *outside* `INSPECT_REJECT_COOLDOWN` — asserting inside it would be asserting that a cooldown does not work.
 - **One fault-isolation guard that is NOT revert-proven, recorded as such.** A distance API raising under comparison is documented as a *concern* rather than a demonstrated failure: on `forever` and `live`, `UnitDistanceSquared` is marked `SecretArguments` only — its returns are plain numbers — while `UnitInRange` on those two branches *is* `SecretReturns`. One client build is all it takes for that to change, so both measurement helpers run their comparisons inside their `pcall` and report "unmeasurable" (which the pre-filter treats as *near*). The test pinning it passes with the fault isolation removed, because `type(dist) ~= "number"` short-circuits before any comparison on a hostile value — so it documents intended behaviour, it does not prove the guard is needed. Listed because a revert-proven claim it could not make is the same class of lie the rest of this file exists to stop.
- **One real defect found by the tests rather than by reading:** the `CanInspect(unit, true)` gate originally called `noteInspectRejected(unit, yards)` on refusal, which tightened the learned-range ceiling to wherever the unit happened to be standing. Wrong twice over — the gate says nothing about distance, and the side effect then blocked a unit that was plainly *close* from ever being inspected. It now records the rejection with no distance attached, so the ceiling is only ever taught by a real refusal.
- **`luacheck` stayed clean.** The two new blocks initially introduced 7 shadowing warnings (`clock`, `requested`, `thrown`, `ci` shadowing the surrounding inspect block) while the file was previously at 0; the new locals are renamed, and the totals before and after this change are identical at 129 warnings / 0 errors in 43 files, all pre-existing.

### Tests that were green for the wrong reason — inspect pipeline

Six in total. Two from the earlier inspect work, four from the "Not in Range" work (listed above as wrong turns 1, 2 and 4).

- The `GetTime`-absent check originally passed because `isCacheFresh` short-circuits on a nil cache entry before ever reaching the clock, and `GetLastCacheTime` returns the *stored* stamp without reading a clock at all. It now drives the real `INSPECT_READY` handler, which forces the read.
- That handler was being invoked as `handler("INSPECT_READY", guid)`, but a frame script's signature is `function(self, event, ...)`. The event name landed in the `self` slot, the whole branch was skipped, and the test was green because **nothing ran at all**.

### Tests that were green for the wrong reason — out-of-range work

Four more, from the "walk out of range" work: the three revert-to-fail probes listed above, plus a first draft of the out-of-range test that counted requests from **every** fallback unit rather than `target`. `SCAN_FALLBACK_UNITS` contains `mouseover` and `focus` too, each of which is legitimately asked once before its own mark is set, so the aggregate assertion was measuring something no one claimed. It passes only when the counter is narrowed to the unit actually under test.
### Harness corrections — delivery, events and the scan

- **`xpcall` varargs shim.** WoW's Lua accepts extra arguments on `xpcall`; stock 5.1 accepts exactly two. Blizzard's own FrameXML relies on this (`xpcall(handlerInfo.handler, CallErrorHandler, self, button, cursorX, cursorY)` on classic_era) and so does the bundled `CallbackHandler-1.0` v7 `Dispatch`, which passes the event name and payload through it. Under stock `lua5.1` every handler received **zero** arguments, so any assertion on callback arguments would have failed for a reason that does not exist in game. The harness now reproduces the client's behaviour.
- **`next` / `xpcall` were missing from the mocked environment.** `run()` wipes the entire `_G` and restores a fixed list that never included them, so `CallbackHandler` captured `local next = nil` at load and **every `callbacks:Fire()` in the suite raised inside `Dispatch`**. No test ever fired a callback, so nothing noticed. This is the first test that does, and it asserts the real `INVENTORY_READY` → `(guid, true, unit)` contract end-to-end.
- **New coverage, all five clients:** scan enqueues an in-range player; skips a fresh cache entry; respects the one-per-tick budget; survives a plate whose unit query raises (and counts it); rejects out-of-range with the *correct per-family* policy (Classic = `CanInspect` true + distance false, mainline = both false); is blocked in combat; and obeys `SetScanEnabled(false)`. Plus the classic range gate (cold reject / recency-is-not-an-exemption / stale entry), ticker registration, watchdog release, the `GetTime`-absent path, and the full rejected-inspect path (escape / count / per-unit single ask / learned ceiling / cooldown expiry / fallback with no nameplates).
- **Roster auto-scan regression guard.** The pre-existing party/raid inspection was already running on the queue ticker before the nameplate scan existed, and the nameplate ticker was *added alongside* it rather than in front of it. Nothing asserted that, which is exactly how a refactor of the pending/watchdog block could have deleted the roster arm silently. It is now asserted on all five clients **with `GetNamePlates` forced absent**, and deleting the roster arm turns it red.
- **Four wrong turns in the "Not in Range" tests, all recorded because each one hid the very bug being fixed.** These are the failures that made a green suite mean nothing, and every fix below was re-verified by reverting it and watching the suite turn red:
  1. **The first version of the escape test could never fail.** It drove the scan with a nameplate present, and the plate walk wraps every plate body in its own `pcall` for fault isolation — so the refusal was swallowed by that guard and the assertion passed with the fix removed. The unprotected path is the fallback; the test now drives that, with `GetNamePlates` returning nothing.
  2. **The first mutation was malformed.** `local ok, err = _G.NotifyInspect, unit` *assigns* rather than calls, so nothing was invoked and the suite stayed green for a reason unrelated to the product.
  3. **Removing the rejection guard did not bite** — because it is enforced at three independent points (`CanInspect`, `requestInspect`, `scanCandidate`), defence in depth. It only turned red once all three were disabled, at which point the request count went from 2 to 9. The same thing happened to the fallback, which has two call sites, and to the hysteresis test, which asserted the behaviour that caused the bug.
  4. **Two assertions were wrong about correct behaviour**, not the reverse: the scan legitimately tries a second distinct candidate after the first is refused, and the learned ceiling legitimately tightens from 40 to 6 once a closer unit is also refused. Both were corrected to assert the real contract rather than the convenient one.
- **Every new assertion was revert-to-fail proven** — twelve mutations, each turned the suite red and was then restored: scan budget, per-plate fault isolation, watchdog release, scan-ticker registration, wall-clock-vs-uptime stamps, the `GetTime` guard, and the roster arm; then, for the "Not in Range" work, the `pcall` around `NotifyInspect`, the per-unit rejection blacklist (all three of its call sites — see wrong turn 3), the learned-range ceiling, the nameplate fallback (both of its call sites), and finally the **hysteresis removal itself**, which is proven by re-introducing the bypass and watching `classic range: recency does NOT exempt a unit that walked out of range` turn red.

### Efficiency and robustness pass — what two audits found that the suite could not

Two read-only audits were run over the whole pipeline before this release was trusted: one tracing every thread between `LibForeverInspector` and the rest of the repo, one on the scan pipeline itself (per-client support, redundant work, wasted calls, state growth). Both were mirror-only for Blizzard claims. What they found, and what changed:

- **The tick walked a cached raid through the entire gate chain.** `inspectQueueTick` checked `UnitExists → isCloseEnoughToAsk → lib:CanInspect` for all 40 raid members *before* asking whether their data was already fresh — so a 40-man raid where everyone was cached cost ~40 distance probes plus ~80 classic-family probes **per 0.5s tick**, roughly 880 engine calls a second, to discover nothing needed doing. Freshness now comes first in all three priorities (target, queue, roster). Measured: `can=0 dist=0 distSq=0` for a cached 40-man raid, against `can=40 dist=40 distSq=40` when the order is reverted.
- **The tooltip was rebuilt twice for every completed inspect.** The library fires `INVENTORY_READY` and `TALENTS_READY` back to back from one `cacheUnitData`, and `main.lua` handled both identically with `GameTooltip:SetUnit` — two full renders (gate chain, text path, and `GetScore` walking 18 item slots) for identical data. The second of an immediate pair is now dropped, keyed on GUID with a short window so a genuine later update still rebuilds.
- **`DoInspect` ran the whole gate chain on every settled render.** It is the addon's hottest path — the tooltip handler calls it on every unit render — and for a unit whose data is already fresh the answer is known from memory. The freshness lookup now comes first.
- **The watchdog's documented 3s window never ran.** A second, earlier release branch (`now > nextInspectTime + 0.8`) always fired first in real time, because the ticker runs every 0.5s — so the branch that increments `timeouts` was unreachable outside a loading screen, `/tacotip diag` under-reported stalled inspects, and a unit that never answered was re-requested at nearly twice the intended rate, forever, while it stayed targeted. One window now, named `INSPECT_PENDING_TIMEOUT`, and it is counted.
- **`INSPECT_READY` released the pending slot for *any* GUID.** A late answer to an earlier request therefore dropped a request that was still in flight: the second unit's own answer could no longer be resolved (a queued or nameplate unit is neither target nor mouseover), so its data was discarded and requested again. The slot is now released only by its own answer — or by a unit that is gone, or a GUID-less event.
- **An uninspected player was shown a specialization anyway.** `GetSpecialization` returned `1` for an uncached unit, which means "the first spec of its class" — so every player not yet inspected read "Arms [0/0/0]" on the classic family or "Arms" on the modern pair until `INSPECT_READY` re-rendered. It returns nil now, as `GetLocalizedSpecName` beside it already did; the callers already gate on nil.
- **The unresolved-unit portrait branch had both halves of its contract inverted.** An *unproven* change (no GUID — every Classic render — or the same GUID) was hidden, re-anchored and re-shown: a `Hide()`+`Show()` on a 3D model frame on every render, for a portrait that had not changed. A *proven different* GUID — the case the comment above the call says must not leave the stale mesh up — passed `keepModel = true`, which means "do nothing at all", so the previous character's face stayed visible while the tooltip described someone else. Now: unproven is a complete no-op, proven-different is a full teardown, and neither re-shows.
- **Dead state removed.** `lib.inspectSuccessTime` was written on every successful inspect and read by nothing in production (only by two test lines); its comment still described a hysteresis that had been deliberately deleted. Gone, along with the two assertions that seeded it — they passed whether or not any hysteresis existed, because the gate never read the field.
- **Diag truthfulness.** The sound-kit half of the guard's work had no counter at all, so a client whose refusals are sound-only showed `probe errors suppressed` climbing with `error speech suppressed` at 0 and nothing to explain it — `error sound suppressed` now exists. `lastError` is labelled "last inspect-call error" because it is set only when the engine *call* raises, never by a refusal delivered as a UI error. And `noteSuppressedRefusal`'s unused `message` parameter is gone.
- **The hover contract, asserted on all five clients.** `tooltip_test`'s "hovering a player NEVER auto-inspects" assertion was **green for the wrong reason**: the mock creates every frame shown, nothing hides `InspectFrame`, and `lib:CanInspect` refuses while the inspect frame is up — so the library issued zero requests for the whole run and the check could not tell "hover never asks" from "the library never asks at all". It would have passed with the entire request path deleted, and it only ran on the two pipeline clients. It now asserts the real contract — hovering **does** inspect, the request is for the hovered unit, and a burst of five renders costs at most one request — on every client, through that client's own delivery. The mock also gained a controllable clock, because with no `GetTime` at all the library reads 0 for every timestamp and its pacing gate can never open twice in one run.
- **The orphan-GUID portrait assertion asserted the wrong contract too.** It drove a proven-different GUID through the unresolved branch and asserted the portrait stayed *shown* — pinning the stale-mesh bug. It now asserts both contracts where each applies: hidden for a proven change, untouched (and not even `Hide()`d) when nothing is proven.
- **Stale comments corrected** in the library (`GetModernSpecializationIcon`'s "the other one is a stub" — it is a full implementation; a line-number reference that had drifted), in the harness (the `CanInspect(unit, TRUE)` claim that contradicted the corrected block in the same file), and in `README.md` (the "raises from inside the call" mechanism, the deleted attribution section, the 28-yard figure, the either-signal range rule, and an `INSPECT_DELAY` of 0.8 that the code sets to 0.4).

**Verification.** `bash Tests/harness/run_all.sh` — 54/54. `TacoTip_Extras/Tests/harness/run_all.sh` — 42/42. `detect_test` passes under lua5.1, lua5.4 and luajit. Every new assertion was mutation-tested — the fix reverted, the assertion red, the fix restored: raid walk gates-first (`can=40 dist=40 distSq=40`); the early watchdog branch restored (never released, `timeouts=0`); the pending slot cleared unconditionally (`ready 0 -> 0`); the tooltip coalesce removed (`SetUnit calls=2`); `GetSpecialization` inventing spec 1 (`spec=1`); the old portrait shape (`shown=true` for a proven change, `Hide() calls=1` for an unproven one); the hover path disabled (3 red on Classic, 5 on the modern pair); pacing removed (`NotifyInspect calls=5` across five renders).

**Deliberately not done in this release**, each recorded in `bench/OPEN-ITEMS.md` with its evidence: memoizing `GetScore` per `(guid, cache time)`; event-driven discovery (`NAME_PLATE_UNIT_ADDED`) instead of the 2s enumeration; bounding `lib.cache`; and wiring `SetScanEnabled` to an options toggle.

### Still outstanding

Read this before trusting any "fixed" claim above.

- **The popup's origin is still NOT attributed — the earlier claim that it is was withdrawn.** What is verified: the sink (`UIErrorsFrame` consuming `UI_ERROR_MESSAGE` and speaking it), Blizzard's own inspect procedure on every branch (`CanInspect(unit, true)` → `NotifyInspect(unit)`, no range check), and the repo's pre-port library gating distance *first* and suppressing the one-argument query's refusal. What is **not** shown anywhere in the mirror: which call produces the refusal, and whether it is delivered synchronously or by event dispatch. The fix therefore covers both candidates rather than naming one — a short attribution window around the addon's own probes, matching the `errorName` `GetGameMessageInfo` returns. **The fix itself is offline-verified only**: the harness reproduces the refusal-and-display behaviour on all five clients, every new assertion was reverted to confirm it fails, and nobody has yet watched it run in a live client. That in-game pass is the one thing this section still owes.
- **`NEARBY_ASK_YARDS` (20 / 40) is still not set from measurement.** The mirror defines **no inspect yardage at all** — `CheckInteractDistance` is documented with names and types only, and the only yardage constant anywhere in FrameXML is the compact-unit-frame 250-yard threshold — so these are deliberately conservative pre-filters, and the number to replace them with is the one the client measures itself: `/tacotip diag` prints `learned max range`, the tightest distance this client has refused at.
- **`INSPECT_INTERACT_DISTANCE_INDEX = 1` is an inference inherited from the pre-port library**, not a verification, and is labelled as such in the code. Index 1 is the **achievement-comparison** button's gate on Wrath and Retail; on Classic Era's loaded unit-popup file no button returns 1 at all; Blizzard's own inspect button declares no distance and is exempt from the gate entirely.
- **The `load_test` mock is still wrong** — it mocks Classic as having no `NineSlice`, which FrameXML contradicts. **The suite therefore cannot catch a border regression on Classic Era**, and "54/54" does not mean the border works there.
- **`currentUnitGUID` is never cleared.** A→B→A therefore tears the portrait down twice, which is by design (two different characters must not share a mesh) but costs a model reload each way; the first render after a `/reload` has no previous guid, so there is nothing to destroy there. Whether the reload is visible is unmeasured.
- **`GetScore` is recomputed from scratch on every render** — ~20 item tables and ~40 `GetItemInfo` calls for data already in memory. Memoizing per `(guid, cache time, stale)` is the largest remaining per-render saving and was deliberately deferred out of this release because it touches the score path. Evidence and the proposed key are in `bench/OPEN-ITEMS.md`.
- **Discovery still enumerates nameplates every 2s** instead of listening for `NAME_PLATE_UNIT_ADDED`, which exists on all five clients. Deferred as a behaviour change, not a defect.
- **`lib.cache` has no eviction.** It grows with every unique GUID inspected and is only cleared by `/reload`. Bounded in practice by session length; recorded rather than capped.
- **`SetScanEnabled` has no UI.** The proximity scan runs unconditionally and cannot be turned off from the options panel — there is no checkbox wired to the setter.
- **None of the portrait work has been confirmed in a live client.** The code is right and the Classic-only defect is revert-to-fail proven, but nobody has watched it run.
- ~~**The error-capture scaffolding is still in.**~~ **Removed in this release**, together with the `hooksecurefunc` capture added while diagnosing: `lib.errorLog`, the `NotifyInspect` wrapper, the `ChatFrame_AddMessageEventFilter` install, the `UIErrorsFrame` capture frame, `lib.inspectLastNotified*` and the `/tacotip diag` attribution section are all gone. What replaces them permanently is two counters — `suppressed` and `suppressedVoice` — beside the existing `learnedRange`, printed by `/tacotip diag`.

### Documentation corrections

Several files in this repository asserted things about the code that were false, and false prose here has shipped wrong fixes four times in this release. The claims below were each checked against the code rather than accepted.

- **`AGENTS.md` carried four false portrait claims**, each corrected with the line that disproves it: the modern overlay still duplicating the inline icon (it is cleared — `main.lua:1906`, `:1992`); `hasDualSpec` claiming dual spec on single-spec modern clients (it is a family test, false on modern by construction); portrait alpha slaved to the tooltip's (the portrait is `SetAlpha(1)`; the only `GetAlpha()` left is inside a comment); and the portrait re-anchored every render (the anchor is gated and runs once per anchor epoch).
- **`AGENTS.md` also recommended the reverted `CanInspect(unit, true)` "range gate" as the fix** — the very call this release backs out. Corrected, and cross-referenced to the `showError` section.
- **`LibForeverInspector`'s `INSPECT_INTERACT_DISTANCE_INDEX` comment claimed "Verified on every supported branch."** It was not. The real enum, read off Blizzard's own call sites, is 0 = guild/team ops, 2 = trade, 3 = duel, 4 = follow, 5 = pet-battle duel, with the base mixin and the inspect button both returning `nil` — index 1 is used by no button on any branch.
- **`NEARBY_ASK_YARDS` was documented as "matching the ~28 yard inspect range" while being 20 or 40.** Neither branch matched. The comment now states the real relationship, the cost of the Classic strictness, and a `TODO(measure)` pointing at the error log.
- **The `UnitDistance` fallback in `inspectDistance` is unreachable on all five clients** and is now labelled as defensive-only, so nobody reasons about behaviour as though it can execute.
- **README described `hasDualSpec` as a four-term predicate** it no longer is, and advertised a 5-second boundary hysteresis the code explicitly refuses to have ("boundary flicker now costs a skipped inspect, not an error popup"). Both corrected.

---

## [0.8.2] — 2026-10-13

> Typography, portrait sizing, a portrait-side control, and the inspect
> regression fixes that closed out the 0.8.1 queue behaviour.

### Changed

- **The tooltip name is 2pt larger than body text.** `applyTooltipFonts` applied
  a single size to every line, so line 1 — the player's name on a unit tooltip,
  the item's name on an item tooltip — was flattened to body size and read as
  just another row. Line 1 now renders at `tooltip_font_size + 2`; body lines
  are unchanged, so the relationship holds at any size the user picks. The
  per-line `SetFont` guard is unchanged, so a settled re-render still issues
  **zero** `SetFont` calls.
- **Portrait base is now `66 x 88`** (was `72 x 96`). Still an exact 3:4 ratio,
  and still an exact integer at every slider stop — `33x44`, `66x88`, `99x132`,
  `132x176`. Both base numbers are even on purpose: the slider runs 50–200 in
  steps of 5, so a half-stop and a 1.5-stop are both reachable, and an odd base
  would round and drift off ratio at those stops.

### Added

- **TacoTip is now licensed under the MIT License**, matching TacoTip Extras.
  The full text ships in `LICENSE`. `THIRD_PARTY_NOTICES.md` credits the four
  bundled libraries, which keep their own terms and are explicitly **not**
  covered by TacoTip's MIT grant: LibStub (Public Domain), CallbackHandler-1.0
  (MIT, Icedragon), LibDetours-1.0 (MIT, kebabstorm) and LibForeverInspector
  (MIT, part of this project).
- **`Invert portrait side`** option, default **off**, next to `Show 3D portrait`.
  Pins the portrait to the opposite side of the tooltip for anyone whose
  tooltips anchor somewhere the automatic rule picks wrong.
  - The resolved side is cached per tooltip, so the flag is part of that cache
    key — without it the checkbox would appear dead until the next scale change.
  - Applies to both the 3D `PlayerModel` and the 2D texture, which share one
    anchor path.

### Fixed

- **Inspect regression fixes.** Classic Era / SoD / TBC Anniversary / Titanforge again require `CheckInteractDistance(unit, 1)` in addition to `CanInspect` (CanInspect is range-agnostic there, so 0.8.1 fired `NotifyInspect` at out-of-range players and stalled the queue); Retail/Forever keep the either-signal rule unchanged. `UNIT_INVENTORY_CHANGED` now flags a cache entry `stale` instead of zeroing its timestamp, so GearScore/iLvl no longer vanish from the tooltip while a re-inspect is pending (or if it cannot run). TacoTip Extras' remote-result cache freshness raised from 10s to 300s (the library's refresh window) so Extras rows no longer disappear seconds after appearing.

### Verification

16 new assertions in `tooltip_test.lua`, covering portrait dimensions at all
four slider stops, an exact `4w == 3h` ratio check per stop, the name/body font
split, and invert off → on → off including the immediate re-anchor.

---

## [0.8.1] — 2026-10-12

> Inspection engine performance, proactive pre-caching, and range responsiveness.
> Eliminates latency by pre-caching player data on target and mouseover events,
> speeds up the background queue ticker from 1.5s to 0.5s with instant `INSPECT_READY`
> chained dispatch, prioritizes actively targeted players, and resolves remote
> inspection deadlocks.

### Added

- **Proactive Target Pre-caching (`PLAYER_TARGET_CHANGED`):**
  Targeting any inspectable player instantly triggers inspection in the background. GearScore, average item level, specialization, and talents are cached before hovering their unit frame or opening manual inspect.
- **Eager World Mouseover (`UPDATE_MOUSEOVER_UNIT`):**
  Sweeping over player characters in the 3D world triggers immediate background inspection queries rather than waiting for tooltip rendering passes.
- **Group Roster Inspection Scanning (`GROUP_ROSTER_UPDATE`):**
  Automatically runs inspection passes over party and raid members as group members join or update.
- **Equipment Swap Invalidation (`UNIT_INVENTORY_CHANGED`):**
  When an inspected player swaps items, their cached profile is immediately invalidated and re-inspected.

### Fixed

- **Remote Inspect "Scanning Equipment..." Deadlock:**
  Corrected `LibForeverInspector` callback firing to include `isInspect` (`true`) and `unit` with `INVENTORY_READY` (`lib.callbacks:Fire("INVENTORY_READY", guid, true, unit)`), matching consumer contracts and preventing `TacoTip_Extras` from rejecting the callback.
- **Non-Targeted Inspect Resolution via `InspectFrame.unit`:**
  When players are inspected via right-click contextual menus (guild roster, chat, `/who`, friends list), they are frequently not current target, focus, or mouseover. `lib:PlayerGUIDToUnitToken` now matches `InspectFrame.unit`, ensuring remote inspects resolve their unit token cleanly.
- **Uncached Item ID Resolution on Remote Inspect:**
  Handled remote inspection situations where `GetInventoryItemID` returns `nil` while `GetInventoryItemLink` returns a valid item string link, extracting the item ID directly from the native link to prevent false contradiction failures.
- **Max-Range Inspect Failure & Terrain Dead Zones:**
  `lib:CanInspect(unit)` now succeeds if either `_G.CanInspect(unit)` or `_G.CheckInteractDistance(unit, 1)` confirms inspect eligibility, resolving false-negative rejections caused by tall mounts, elevation changes, or 28-yard border thresholds.
- **Inspection Queue Throttle & Idle Latency:**
  Tightened `INSPECT_DELAY` from 1.5s to 0.8s on modern clients (1.0s on Classic). Replaced the static 1.5s background ticker with a 0.5s ticker, and chained next-queue dispatch immediately upon `INSPECT_READY` arrival, completely eliminating idle delays between sequential player scans.
- **Specialization Lookup & Unused Variable Resolution in `LibForeverInspector`:**
  - Resolved unused `localized` parameter in `lib:GetSpecializationName(class, specIndex, localized)`: queries modern `GetSpecializationInfoForClassID` on Retail/Forever and `lib.spec_table_localized` across localized clients (`deDE`, `esES`, `koKR`, `ruRU`, `zhCN`), falling back gracefully to English defaults.
  - Resolved unused `class` and `specIndex` parameters in `lib:GetSpecializationIcon(class, specIndex)`: dynamically extracts the specialization icon via `GetSpecializationInfoForClassID` on Retail/Forever and via `lib:GetTalentInfoByClass` on Classic.
  - Added `lib:IsAnniversary()` and `lib:IsTitanforge()` convenience aliases.
  - Hardened TBC Anniversary client detection via `clientBuildMajor == 2` (`20506`) alongside Blizzard's native `WOW_PROJECT_BURNING_CRUSADE_CLASSIC` constant.
- **Target Prioritization:**
  The background inspect loop now checks and inspects your actively selected target ahead of queued or group roster background iterations.
- **Pending Inspect Timeout:**
  Reduced the pending inspect timeout from 3.5s (`nextInspectTime + 2.0`) to ~1.6s (`nextInspectTime + 0.8`), recovering gracefully if a target moves out of range or disconnects.

---

## [0.8.0] — 2026-10-11

> GearScore correctness. This release introduces value-level numerical assertions
> across all equipment combinations, client families, and inventory configurations.
> It fixes two-handed weapon weighting, isolates Titan's Grip dual-wielding, hardens
> asynchronous item loading, synchronizes Hunter weapon calculations, and aligns
> quality colour bands.

### Fixed

#### Two-handed weapon math & Titan's Grip dual-wielding

In standard GearScore architecture:
- Standalone two-handed weapons (`INVTYPE_2HWEAPON`) occupy slot 16 with slot 17 empty. Because they fulfill both weapon hand budgets, they possess a `SlotMOD` of `2.0` so that a solo 2H weapon contributes equivalent GearScore (`621`) to a 1H weapon (`310`) plus Shield/Offhand (`310`).
- **Titan's Grip** is the WotLK Fury Warrior talent allowing players to equip 2-handed weapons in one hand alongside another weapon or shield in the offhand.
- Only when an offhand item is equipped alongside a 2H weapon (`mainHandLink and offHandLink`) does dual-wielding occur. In this case, `TitanGrip = 0.5` scales each 2H weapon down to 1.0x so dual 2H wielders total `310 + 310 = 620` weapon GearScore, preserving exact parity.
- Standalone 2H wielders (Ret Paladins, Arms Warriors, Casters with staves, Hunters) retain their full 2.0x weight (`1241` total with head + legs).

#### Asynchronous item loading resilience & nil safety

- Guarded `GetItemInfo` against nil parameters and unhandled multi-returns.
- Hardened `scoreFromItemInfo` to ensure uncached items cleanly return zeroed scalar scores (`0, 0, 0.1, 0.1, 0.1, 0`) while triggering `C_Item.RequestLoadItemDataByID` without arithmetic errors.

#### Hunter weapon scaling parity

- Unified Hunter melee weapon (`0.3164x` for mainhand and offhand) and ranged weapon (`5.3224x` for bows, crossbows, guns, thrown) multipliers across character aggregate scoring (`TT_GS:GetScore`) and tooltip item queries (`TT_GS:GetItemHunterScore`).

#### Item colour band no longer described the score shown

In `scoreFromItemValues` the colour band was computed from the **slot-mod-free**
base, with a hardcoded `* 1` standing in for `SlotMOD`:

```lua
local Red, Green, Blue = TT_GS:GetQuality((floor(((ItemLevel - Table[ItemRarity].A) / Table[ItemRarity].B) * 1 * Scale)) * 11.25)
GearScore = floor(((ItemLevel - Table[ItemRarity].A) / Table[ItemRarity].B) * GS_ItemTypes[ItemEquipLoc].SlotMOD * Scale * QualityScale)
```

The number printed to the user includes `SlotMOD`; the colour does not. Two
items of identical item level and rarity therefore wore the same colour while
displaying different scores:

| Item (ilvl 200) | Score shown | Band before |
| :--- | ---: | :--- |
| head (`SlotMOD` 1.0) | 310 | Artifact |
| 2H (`SlotMOD` 2.0) | 621 | **Common** — a 621 GS weapon painted as junk |
| ranged (`SlotMOD` 0.3164) | 43 | Superior |

Upstream GearScore 3.1.20 decouples the band the same way, using `12.25` on the
same slot-mod-free base, so the decoupling is **also inherited**. The
`12.25 -> 11.25` constant change, however, is **ours**.

The band is now applied to the computed `GearScore` through a named constant,
`ITEM_BAND_SCALE = 11.25`, so the colour is a pure function of the number
printed beside it. The ~11x rescale is deliberately **kept**: applied to a raw
score, every small item would flatten into the "Trash" band.

### Which items change tooltip colour

**This is the only user-visible colour change in 0.8.0.** Every item whose
`SlotMOD` is below 1.0 shifts band, because those are the items whose displayed
score was most decoupled from their colour. They now colour like the slot they
occupy rather than like a head:

| Slots | `SlotMOD` |
| :--- | ---: |
| ranged, thrown, ranged-right, relic | 0.3164 |
| trinket, neck, finger, wrist, cloak | 0.5625 |
| shoulder, waist, feet, hands | 0.7500 |

`SlotMOD` 1.0 items (head, chest, legs, 1H weapons, shield) keep their existing
band, and the 2H at 2.0 moves up from the far too low "Common" to its true band.

Character **totals** are unaffected: `main.lua` passes `TT_GS:GetQuality(total)`
unrescaled, and that stays. Item scores and character totals are different
domains — the bands are sized for a total — and the two are deliberately **not**
unified.

### Tests

`Tests/harness/gearscore_test.lua` is new and is the first harness in the project
to assert a GearScore **value**. It drives the real `gearscore.lua` against a
mocked inventory and asserts:

- per-item score literals derived by hand from the formula (`310`, `621`, `98`, …);
- the Titan Grip half-weight, and an exhaustive enumeration of **reachable**
  weapon states;
- item colour-band consistency across every slot at several item levels and
  rarities, including the ones that land on a clamp;
- the low-slot guard — a ranged item must wear *its own* score's band, never a
  head's;
- two known full sets of known items producing known totals (3624 for 1H+shield,
  3314 for 2H-no-offhand), the first such assertions in the suite.

Every fix was reverted to confirm the test **fails**, then restored:

- reverting the Titan Grip fix → **6 assertions fail** (`1241` vs `930`, delta
  `621` instead of `310`, SET B `3625` vs `3314`);
- reverting the colour-band fix → **2 assertions fail** (a ranged item comes back
  wearing the head's `0.92/0.10/0.10` while its own score's band is
  `0.12/0.81/0.04`).

The one-handed set stays green under both reverts — it is the control proving
the Titan Grip fix does not disturb a legitimate 1H loadout.

### Wrong turns

- **Reading the Titan Grip guard was not enough.** It reads as a perfectly
  reasonable sanity check — "only halve the main hand if there is also an
  offhand". It took enumerating all 49 realistic inventory combinations to
  prove `TitanGrip` was always `1.0`. The dead assignment is invisible to the
  eye and obvious to a table.
- **A mock bug presented as a product bug.** Every `GetScore` assertion first
  returned `0` while every `GetItemScore` assertion passed. The product was
  fine; the harness mock was not: `function CI:GetInventoryItemMixin(_, guid, slot)`
  declares `self` *implicitly* in a colon definition, so the extra `_` shifted
  every argument one place left and `slot` was always `nil`. It cost real time
  and pointed squarely at the wrong file. The same lesson as the seven green
  lies already recorded: **never accept a green test you have not seen fail**,
  and when everything returns zero, suspect the mock before the product.
- **The first enumeration asserted a state WoW cannot produce.** `2H + offhand`
  is impossible, and asserting it froze upstream behaviour that only the
  fictional state can reach (`gearscore.lua` applies `TitanGrip` to the offhand
  too, so that state scored 1085 against an expected 1240). The same mistake
  made the first "known full set" literal wrong: it contained a 2H *and* a
  shield and scored 3469, i.e. `3624.5 - 155`, the shield counted at half.
  Neither number was pasted in — both were re-derived by hand from the formula.

---

## [0.7.9] — 2026-10-10

> Portrait and border correctness. **Verified in a live client 2026-10-10** on
> Classic Era, TBC Anniversary and WotLK Titanforge. Retail and WoW Forever are
> under active test; see *Known limitations* for what is still open on them.

### Fixed (2026-10-10 re-verification pass)

- **Right-click inspect stripped all gear from the paperdoll on Retail and WoW Forever.**
  `LibForeverInspector.lua` was calling `ClearInspectPlayer()` inside its `INSPECT_READY`
  handler immediately after caching the inventory links. Because `ClearInspectPlayer()`
  purges the inspected unit from the WoW client engine, Blizzard's native
  `InspectPaperDollItemSlotButton_Update` found `GetInventoryItemTexture` returning nil
  for all 18 equipment slots, resetting all buttons to their empty background texture.
  Removed the premature `ClearInspectPlayer()` call from `INSPECT_READY` (Blizzard only calls
  it on `InspectFrame_OnHide`), added `InspectFrame.unit` fallback matching in
  `LibForeverInspector` for non-targeted party/raid inspects, and ensured `ADDON_LOADED`
  registers inspect hooks and `InspectGuildFrame_Update` protection when `Blizzard_InspectUI` loads.

- **IDE Lua Diagnostics `redundant-parameter` warning in `LibForeverInspector.lua`.**
  `lib:GetInventoryItemMixin` called `C_Item.GetInventoryItemLink("player", slot)` when `C_Item`
  was present. In standard Blizzard FrameXML (`PaperDollFrame.lua` and `InspectPaperDollFrame.lua`),
  the engine exposes and uses the global `GetInventoryItemLink("player", slot)` across all
  client versions (Classic Era through modern Retail). EmmyLua / WoW API IDE stubs do not define
  a 2-argument signature on `C_Item`, raising a `redundant-parameter` diagnostic error.
  Standardized to direct global `GetInventoryItemLink("player", slot)` without warnings or overrides.

- **Localization audit & formatting token parity across all 11 locales.**
  Audited all 11 locale files (`deDE`, `enUS`, `esES`, `esMX`, `frFR`, `itIT`, `koKR`, `ptBR`,
  `ruRU`, `zhCN`, `zhTW`), verifying 100% key completeness (261/261 keys per locale) and
  exact `%s`/`%d` format specifier parity with zero syntax errors or format mismatches.

- **The 3D portrait blinked continuously on every unit-frame hover.** The 0.7.9
  fix below removes the per-render strobe but does not remove the cause. When
  `tooltipUnit` fails to resolve, `onTooltipSetUnit` called
  `clearTooltipVisuals(tooltip)` with **no `keepModel` argument**, so it
  defaulted to false and destroyed the PlayerModel on every such render. And the
  `data.guid` fallback immediately above only ever tries **`mouseover`** and
  **`target`** — so hovering a *unit frame*, which passes that frame's own unit
  (`player`, `target`) rather than the mouseover, missed both and failed to
  resolve. On Retail and WoW Forever the post-call runs before the client's own
  `Show()`, which is when those reads are least reliable, so it failed on
  nearly every frame-hover render. Live counters read **`portrait hide: 69`
  against `unit renders: 70`**.

  The tooltip still *looked* right throughout, because that path does not clear
  the already-rendered lines: only the portrait was obviously wrong.

  Fixed by comparing guids rather than guessing a unit token from one — the
  portrait survives when the incoming guid matches the unit already rendered,
  and still tears down when it differs or is absent. `OnTooltipCleared` /
  `OnHide` remain the real recycle boundary and are unaffected.

- **Stationary hover on PlayerFrame / TargetFrame constantly destroyed and reset tooltip visuals on Retail.**
  In modern Blizzard FrameXML (`UnitFrame.lua:389` & `GameTooltip.lua:457`), `GameTooltip_OnUpdate`
  runs every 0.2s (`TOOLTIP_UPDATE_TIME`) and calls `owner:UpdateTooltip()` (`UnitFrame_UpdateTooltip`).
  Every 200ms, `UnitFrame_UpdateTooltip` calls `GameTooltip_SetDefaultAnchor` -> `tooltip:SetOwner(parent, "ANCHOR_NONE")`.
  In the C++ client, `SetOwner` resets ownership and hides the tooltip, firing `OnHide`.
  Next, `GameTooltip:SetUnit` calls `TooltipDataHandlerMixin:InternalProcessInfo` -> `self:ClearLines()`,
  firing `OnTooltipCleared`. Finally, Blizzard calls `GameTooltip:Show()`.
  Because TacoTip's `OnHide` and `OnTooltipCleared` hooks treated these transient 200ms internal refreshes
  as genuine tooltip dismissals, they ran `clearTooltipVisuals` 5 times per second: resetting the border
  to default, un-anchoring and hiding the 3D portrait, and hiding `TacoTipPowerBar`.
  Fixed by implementing `isUnitFramePeriodicUpdate(tooltip)`, which checks whether `owner.UpdateTooltip`
  and `owner.unit` match the currently rendered unit GUID. If true, the transient `OnHide` and
  `OnTooltipCleared` skips visual destruction, preserving the 3D model, power bar, and border overlay rock-solid
  with zero flicker. When the mouse genuinely leaves (`UnitFrame_OnLeave` sets `UpdateTooltip = nil`),
  full teardown executes as intended.
  Also corrected `applyTooltipBorderOverlay`'s texture guard from `~= "Interface\\Tooltips\\UI-Tooltip-Border"`
  to non-empty border check, ensuring border alpha and tinting apply correctly to default tooltips.

- **Auto-inspection restored with range, throttle, and cache safeguards.**
  Automatic inspect queries on player mouseover and nearby party/raid members are restored
  so GearScore, iLvl, and talents populate without requiring manual inspect. The previous
  out-of-range "Cannot Inspect" sound/error and render spam are fully resolved:
  - Range check via `CheckInteractDistance(unit, 1)` prevents inspecting targets beyond ~28 yards.
  - 5-minute cache TTL (`CACHE_REFRESH_DELAY`) eliminates redundant inspections for cached players.
  - 1.5s rate-limit throttling and queue ticker prevent server request spam.
  - Active Blizzard `InspectFrame` is respected so manual inspects are never interrupted.

- **A guildless inspected player rendered blank.** Verified on `origin/live`,
  `Blizzard_InspectUI/Mainline/InspectGuildFrame.lua:22`:

  ```lua
  InspectGuildFrame.guildRealmName:SetFormattedText(INSPECT_GUILD_REALM, guildRealmName)
  if (guildFactionName and guildNumMembers) then   -- these two ARE guarded
  ```

  `guildRealmName` is nil for any player with no guild and `SetFormattedText`
  raises on nil, so the frame dies mid-update. **This is a Blizzard defect, not
  ours — vanilla Retail does it too** — but auto-inspecting on hover made it a
  constant occurrence. Wrapped so it cannot kill the frame. Only the modern
  global form is wrapped; the Cata branch guards every value it formats.

- **Another addon adding a tooltip line had that line erased.** This addon
  remembers the line **index** of the guild and level lines it wrote
  (`TacoTipGuildLineIndex = 2`, `TacoTipLevelColorLineIndex = 3`) and blanks
  those indices on the next clear. Any addon that adds a line — Baganator's
  tracked item amount, Details' item level — shifts every index after it, so the
  remembered index then points at *their* line and the blank destroys it.
  Reported as "item amounts break on the second mouseover". Fixed by remembering
  the text written and blanking a line only while it still holds it.

- **The harness could grade a tree other than the one under test.** All eight
  harnesses pinned the literal `/home/sam/TacoTip-Gearscore-TBC/TacoTip_Forever/`.
  Relocating the addon, corrupting every Lua file in the copy and running the
  copy's own harness reported **"50 passed, 1 failed"** — 50 of 51 invocations
  green with every production file a syntax error, because they loaded the
  pristine original at that literal path. Only `textures_test` failed, because it
  was the sole harness deriving its own location. All eight now derive the root
  from `arg[0]` through `Tests/harness/root.lua`, which errors loudly if the root
  has no `textures.lua` in it. The same corrupted copy now reports **5 passed, 46
  failed**.

### Fixed

- **The 3D portrait strobed on Retail and WoW Forever only.** Root cause, read
  out of the client's own FrameXML rather than inferred: `TooltipDataHandler.lua`
  runs `ProcessLines()`, then `tooltipPostCall`, then `ProcessTooltipPostCalls`,
  and only *then* `self:Show()`. Our entire unit post-call handler therefore
  executes against a tooltip that has never been laid out or presented. Classic
  has no such ordering — `OnTooltipSetUnit` is an engine-fired script with
  nothing wrapped around it — which is exactly why this never appeared on any
  Classic client. Two cosmetic defects became the visible bug:
  - The portrait set its alpha from `tooltip:GetAlpha()` on every render, and a
    permanent `OnUpdate` polled the same value every 0.05s. On the modern pair
    that read sampled a frame Blizzard had not shown yet, so the portrait was
    assigned an unusable value and then walked back up by the poll — the drop,
    and the slide back into frame. **The alpha slave and the `OnUpdate` are both
    gone.** The portrait keeps its own alpha of 1.
  - The anchor chose its left/right side from `tooltip:GetRight()` against the
    screen width, then `ClearAllPoints()` and re-anchored on *every* render. Off
    an unlaid-out frame `GetRight()` is 0, so the side-flip decided from garbage
    each time. **The side is now cached** and recomputed only when the portrait
    scale changes or the tooltip is genuinely shown. An unshown frame resolves
    to the correct default side, so the first anchor is still right.

- **28 fabricated texture paths removed from the border and background lists.**
  This is a correction of a mistake shipped in `0.7.9` mid-session, recorded here
  rather than quietly reverted.

  An earlier pass in this same release added `Interface\BackdropTextures\*` paths
  and made `UI-Backdrop-Edge` the modern default, on the claim that the Classic
  family is built around `UI-Tooltip-Border` while Retail and WoW Forever are
  built around the `BackdropTextures` set. **The mechanism was real; the art
  paths were invented.** There is no `BackdropTextures` directory on Retail at
  all.

  Verified against `Gethe/wow-ui-textures`, the art mirror that sits beside
  `wow-ui-source`: the path returns **404 on live**, while `Tooltips/` holds 35
  files there and 23 on `classic`, so the absence is real rather than an
  incomplete mirror. `BackdropTextures` also appears in zero commits across the
  whole `wow-ui-source` history, on all seven branches. Nine fabricated border
  entries and nineteen fabricated background entries have been removed.

  **Why this mattered enough to catch:** a wrong texture path does not raise. It
  renders a missing-texture placeholder, so the defect would have looked broken
  while reporting nothing — the worst failure mode available.

- **Three real Retail tooltip borders added.** Verified present in the `Tooltips/`
  art mirror on live but **absent on classic**: `UI-Tooltip-Border-Azerite`,
  `-Corrupted` and `-Maw`. These are the texture-path equivalents of Blizzard's own
  modern `TooltipAzeriteLayout` / `TooltipCorruptedLayout` / `TooltipMawLayout`
  NineSlice layouts. All three are 256×32, so each now declares its own
- **Expanded verified Blizzard native borders and removed `None`.** Added official FrameXML borders from `Blizzard_SharedXML/Backdrop.lua`:
  `UI-Arena-Border` (edgeSize = 32), `UI-SliderBar-Border` (edgeSize = 8), `UI-Toast-Border` (edgeSize = 12),
  `TextPanel-Border` (edgeSize = 16), and `UI-TutorialFrame-CalloutGlow` (edgeSize = 16). Removed the non-texture placeholder `None`
  from border selections and resolution paths.

- **The default border is now resolved in one place** rather than from a literal
  repeated across three files that had to be kept in step by hand.
  `TT:GetDefaultTooltipBorder()` in `textures.lua` is the single source and
  `GetResolvedTooltipBorder` calls it. The value is
  `Interface\Tooltips\UI-Tooltip-Border`, confirmed present on both the retail
  and classic art mirrors and byte-identical between them (128×16) — one path
  serving all five clients. It is a **fallback**, not a stored preference: a
  player who has chosen a border keeps it on every client.

  It also repairs a defect earlier releases described as a shipped default: the
  configured value `"Tooltip enlarged"` matches **no entry** in
  `TT.builtinTooltipBorders`, so it has always fallen through to this fallback
  rather than naming anything.

- **The default border edge size moves from 14 to 16.** The verified tooltip
  border is 128×16, so it slices cleanly at 16. The edge-file spec requires the
  slice size to be a multiple of 8, and 14 is not — which is what produced a
  slightly ragged edge. `TT:GetResolvedTooltipBorderEdgeSize()` now resolves it,
  preferring a choice's own declared size over the player's global setting. A
  hand-edited fractional saved value is now floored: `SafeSanitizeConfig` range-
  checks `tooltip_border_edge_size` but never rounded it, so a saved `16.5` passed
  both checks and reached `SetBackdrop`, whose edge sizes must be whole pixels.

  > **Verification limits, stated rather than glossed.** The art mirror's `live`
  > branch was last committed 2022-08-20 (9.2.7), while the FrameXML mirror is
  > current. The existence proofs are therefore directly verified as of 9.2.7,
  > with current-day support being that retail addons pushed in September 2026
  > still reference `UI-Tooltip-Border`. **WoW Forever has no art mirror at all**
  > (the mirror carries only `live`/`ptr`/`beta`/`classic`), so its art is
  > inferred from shared code, not observed. Every *other* directory named in the
  > border and background lists — DialogFrame, CharacterFrame, Covenant, and so
  > on — is **also unverified**; only the `Interface\Tooltips\` family above was
  > actually checked. Treat the rest as candidates, not confirmed paths.

- **The portrait side was frozen for the life of the `GameTooltip` frame.** The
  0.7.9 fix above caches the left/right decision in tooltip state and recomputes
  it only when the cache is absent, the scale changed, or the frame is shown and
  not yet anchored — and it latches `portraitAnchored` to true. Those two fields
  were written in exactly one place and read in exactly one place, and *nothing
  ever cleared them*: `clearTooltipVisuals` tore down timers, class colour, border,
  guild and level lines, portrait, spec icon, power bar and padding, and not the
  side cache. So the very first hover decided the side until `/reload`. With
  `anchor_mouse` on, hovering a unit on the far side of the screen left the
  portrait hanging off the wrong edge.

  Fixed by resetting the cache on the tooltip **recycle** boundary. That word is
  load-bearing and the first attempt got it wrong — see *Wrong turns* below.

- **`tooltip_max_width` never applied to item tooltips.** `applyTooltipMaxWidth`
  had exactly one call site, inside `onTooltipSetUnit`. `itemToolTipHook` applied
  the font, the backdrop and the border overlay but not the width cap, so the one
  tooltip type that reliably carries a long line was the one type the option did
  nothing for. The item path now caps too.

- **Per-render change guards.** Five writes happened on every render whose result
  was already on the frame. Each now compares what it last applied and skips an
  unchanged write, mirroring the idiom `applyTooltipMaxWidth` already used for
  the line width cap and the one `SetMinimumWidth` already used for the tooltip's
  minimum width:
  - `applyTooltipFonts` called `SetFont` on all twenty pooled lines every render,
    through `callLabeled` — a widget lookup, a `type()` and a `pcall` per call —
    and on the item path once more per hover. It also runs *after* the `SetText`
    loop, so each call invalidated the text measurement that loop had just
    produced. Now guarded on `line._tacoTipFont` / `_tacoTipFontSize`; a line the
    pool has just handed out carries nil and is picked up on the next render with
    no invalidation hook.
  - `applyTooltipBackdrop` rebuilt a backdrop info table *and* a nested insets
    table on every render, and `SetBackdrop` reassigns the backdrop, re-applies
    both colours and re-tiles the edge texture. The insets table is now a module
    constant, and a signature of exactly what the active branch draws
    (`edgeFile` + `edgeSize`, plus `bgFile` only on the legacy branch that
    actually draws a background) skips the call. `tooltip_border_alpha` is
    deliberately *not* in the signature: it is applied by `SetBackdropBorderColor`
    in `applyTooltipBorderOverlay`, a different call on a different path, so an
    alpha change must not drag a re-tile along with it.
  - The power bar re-asserted both of its anchors every render; the tooltip's
    padding was re-set every render (`SetPadding` re-lays out the tooltip); the
    clamp insets were set with no guard at all, not even a capability check; and
    the wide-style continuation line was re-anchored every wide render. All four
    now compare.
  - `PowerBarColor[power] or {}` allocated a five-field table on every power-bar
    update — on `UNIT_POWER_UPDATE`, `UNIT_MAXPOWER`, `UNIT_DISPLAYPOWER` and
    once per render — and dropped it on the next line. It was the last bare table
    literal in a pipeline otherwise built on pooled buffers. Replaced by a shared
    module-local constant; the fallback colour is unchanged, including the `or 1`
    on blue that makes an unkeyed power type render blue rather than black.

### Wrong turns

Recorded because each of these cost real time and each would have looked like a
passing test.

- **The portrait fix was declared done on a test that could not see the bug.**
  The suite reported "anchored once across 5 re-renders" as green while the
  portrait blinked on every unit-frame hover, because
  `tooltip_test.lua:2256` pins `GT.__shown = true` for the modern block — the one
  value the modern client does *not* have at post-call time. The portrait was
  still destroyed on ~99% of renders; the test simply never drove the render
  that destroys it. Re-measuring in a live client is what caught it.

- **The existing test suite explicitly dismissed the case that broke.** The
  data-gated resolution test asserted *"the realistic case is a hover, where
  `data.guid` is the mouseover"* — so every modern test drove `GetUnit` and
  `TooltipUtil.GetDisplayedUnit` to nil and asserted nothing about the teardown
  that follows. A unit frame passes its *own* unit, not the mouseover. The
  assumption was reasonable and wrong, and it is the reason the path had no
  coverage.

- **`lastInspectGUID` was declared inside the function it was meant to persist
  across.** A dedupe variable declared in `onTooltipSetUnit` is reset to nil on
  every call, so it deduplicated nothing — the change looked right and was
  inert. `luacheck` caught it as *"value assigned to variable is unused"*, which
  is the only reason it was caught before shipping. The dedupe was then made
  moot by removing auto-inspect entirely.

- **A first draft of the inspect guard referenced an undefined global and
  wrapped the wrong function.** It guarded both the modern global and the
  Classic mixin but called the global from the mixin branch. Rewritten to wrap
  only what exists — and only the modern form, since the Cata branch already
  guards every value it formats.

- **A side-by-side simulation of the two anchor implementations produced
  identical numbers for both, which was the tell that it was wrong.** The state
  was being reset per *render* instead of per *hover*, destroying the very cache
  under test. Discarded and rewritten. The portrait diagnosis does not rest on
  that simulation — it rests on `TooltipDataHandler`'s own source, and on live
  counters.

- **A control assertion was written for the Baganator fix and then removed.**
  The companion check — that our *own* line still gets cleared — is not
  observable in the current mock: the line's `__text` reads back as a table for
  every line regardless of how it was set. Shipping it would have been the
  eighth instance of a green assertion that cannot fail for the right reason, so
  it was deleted and the gap documented instead. That half of the fix is verified
  by reading and by in-game test, not by the harness.

- **A revert experiment silently tested the wrong tree.** Because the harnesses
  hardcoded an absolute path, a relocated copy graded the original and reported
  the *same* failures as the fixed run — which read initially as "these
  assertions have no teeth". They did have teeth; the experiment was measuring a
  different checkout. This is the same root cause as the harness fix above, and
  it was found twice before it was understood.

- **A revert script that asserted on a stale copy produced a green revert that
  never reverted anything.** The bite-check for the edge-size memo was run by
  rewriting `options.lua` through a scripted set of substitutions. Three
  consecutive attempts failed on an `AssertionError` *after* some substitutions
  had already been applied in memory, and because the write is the last statement
  the file on disk was untouched — so the "reverted" run reported the same eight
  failures as the fixed run, and for the wrong reason. The first honest signal was
  `luacheck` reporting the memo slots as `never accessed`, which is what a real
  revert looks like. **A revert is only evidence once the static analyser agrees
  the code is gone**, so the check now runs `luacheck` before trusting the
  output.

- **The portrait side cache was first reset unconditionally inside
  `clearTooltipVisuals`, and that put back the bug 0.7.9 had just fixed.**
  `clearTooltipVisuals` is not the recycle boundary it looks like:
  `onTooltipSetUnit` calls it at `:1392` on *every* successful unit render, not
  only on a recycle. So an unconditional reset cleared the latch on every
  re-render as well, and since a GearScore item load re-drives the render many
  times for one character, the portrait went back to re-anchoring per render.
  The existing `portrait is anchored once across 5 re-renders` assertion caught it
  on the modern pair — `anchored 3 times across 5 renders` — which is the fifth
  time in this project that a green suite measured nothing. The reset is now
  keyed on `keepModel`, which the addon already computes for exactly this
  distinction: true means "same character, re-rendered" (a completing item load,
  a border refresh) and is the one case where the layout has not changed; false
  means a genuine recycle or a genuine unit change, and both are a new layout.

- **The mock's `ClearLines` destroyed the line pool, which made FIX 2's guard
  untestable rather than merely untested.** It was modelled as `w.__lines = {}`,
  so every line the addon saw on every render was a brand-new `FontString` with
  nothing remembered. A per-line change guard could then never skip anything — it
  was always looking at a first render — and the mock made "apply it every
  render" look like the only possible behaviour. The real client creates the line
  `FontString`s once and reuses them, which the addon's own comment at
  `main.lua:101` states outright ("the pooled lines are reused across hovers").
  The mock now keeps the pool. This also means a render that stops early now
  leaves its state on the frame, which exposed a self-sustaining failure: clearing
  a tooltip blanks lines 2 and 3 on entry, an early return leaves them blank, and
  the *next* render then trips the "player with no level line" guard at `:1429`
  and stops early too. The new tests therefore re-seed the tooltip when they hand
  it back.

- **Five mock methods the new tests count were `function() end`.** `SetFont`,
  `SetBackdrop`, `SetPadding`, `SetClampRectInsets` and `SetStatusBarColor` all
  discarded their arguments and returned nothing observable, so an addon that
  re-applied the same font forty times a render and one that set it once looked
  identical. This is the same class of defect as the hardcoded `GetAlpha` above,
  and it is why none of the five had a test. All five now count, and the four that
  matter record their arguments as well, so a guard can be shown to have *applied*
  something rather than skipped everything.

- **A fixed KB threshold for the power-bar allocation check passed on two
  interpreters and failed on the third.** Identical code measured 3.44 KB on
  `lua5.1`, 2.19 KB on `lua5.4` and 2.30 KB on `luajit` over 20 updates, and the
  `luajit` figure is mostly one-off JIT compilation rather than per-update cost —
  so the assertion was a coin flip there. Subtracting a hand-written control loop
  fixed most of it but not all: ~0.10 KB per update of interpreter overhead
  survived, because the control does not make the same calls and so is not
  equivalent work.

  What works is measuring the **same closure twice and changing only the power
  token**. Token `0` is a key of the mock's `PowerBarColor`, so the lookup
  succeeds and the old `or {}` never runs; the probe token is not a key, so it
  runs once per update. Every other call is identical, on the same interpreter, in
  the same run, so the difference between the two is the fallback expression and
  nothing else.

  **With the `or {}` restored, that check fails 4/4 on `lua5.1` and 4/4 on
  `lua5.4`, and passes 4/4 on `luajit`.** LuaJIT's JIT removes the table before it
  is allocated — constructed, read three times and dropped inside one basic block,
  so it never escapes — and no assertion can see a defect the interpreter has
  already optimised away. `lua5.1` is what WoW ships, so that is the measurement
  that counts. The check is honest about this rather than silently weak: its
  detail string names the interpreter when the reference allocation is itself
  invisible, and the behavioural half of the pair (an unkeyed power token still
  resolves to the fallback colour) runs everywhere.

- **The `unpack` fix from earlier in this release, and what it cost to find.**
  Recorded in full under *Testing* below.

- **`next()` is nil in the offline harness, and a diagnostic reached for it.**
  A debug print added while diagnosing why the Pawn control assertion would not
  pass used `next(REALG.PawnCommon.Scales)` to echo the registered scale name, and
  took the whole harness down with `attempt to call global 'next' (a nil value)`.
  The same rule that forbids `next()` in addon diagnostics applies to the harness:
  it is a nil in the sandbox, and a diagnostic must never be the thing that fails.
  `rawget` on the known key is the correct accessor here.

### Testing

- **The harness resolved its own root, and until 2026-10-10 it did not.** All
  eight harnesses pinned the literal path `/home/sam/TacoTip-Gearscore-TBC/…`, so
  a relocated copy, worktree, CI runner or second machine graded the *original*
  checkout. The corrupted-copy proof is in *Fixed* above: 50 of 51 invocations
  green with every production file a syntax error, and 5 of 51 after the fix.
  All eight now share `Tests/harness/root.lua`, which derives the root from
  `arg[0]` and raises if that root has no `textures.lua` in it — a bad path must
  fail loudly, never silently grade a neighbour. Re-running the suite from the
  addon directory still resolves to `.` and still passes.

- **Three new assertions, each reverted to confirm it fails before being
  restored.** A frame hover whose unit cannot resolve must not tear the portrait
  down (red at `portrait hide went 10 -> 11` on FOREVER and RETAIL); hovering a
  player must never call `NotifyInspect` (red at *"called 10 time(s) across 10
  renders of 2 different players"*); and a line at a remembered index that is no
  longer ours must not be touched by the clear. The inspect one required
  instrumenting `NotifyInspect` with a counter, because the mock discarded it —
  an addon that inspected every player was indistinguishable from one that
  inspected none.

- **The suite now runs under three interpreters, and the third one found a real
  test defect.** `bash Tests/harness/run_all.sh` defaults to `lua5.1`, which is
  what WoW ships and what the addon targets. It also passes under `lua5.4` and
  under `luajit`; `LUA=<interp>` selects one. The 25 `lua5.4` failures that
  prompted this were one cause: `unpack` is a global in 5.1 and moved to
  `table.unpack` in 5.2, so the bare global is nil on 5.4. Nine call sites across
  five harness files, all of them the `xpcall` trampolines that replay saved
  varargs and the two mock colour getters that return a triple. It is not an
  addon bug — `unpack` appears nowhere in the shipped files. The signature is the
  dangerous part: a nil `unpack` there throws inside the trampoline, `safeCall`
  swallows the error, and the pipeline simply emits no lines, so a dozen
  assertions fail on an empty tooltip instead of naming the cause.

  `luajit` then earned its place by refusing a GC-delta threshold that `lua5.1`
  and `lua5.4` both accepted; that is recorded under *Wrong turns*.

- **The border-thickness slider silently did nothing for three of the borders.**
  `GetResolvedTooltipBorderEdgeSize` returns a choice's own `edgeSize` *before* it
  ever reads `tooltip_border_edge_size`, and the three themed 256×32 borders
  declare 32. The slider stayed enabled and still showed the player's stored
  value, so a drag did nothing and nothing said why. It now disables itself for a
  border that carries its own geometry, and shows the declared size instead of the
  ignored setting.

- **The border-thickness help still claimed a 14px default.** 0.7.9 moved the
  default 14 → 16 (14 is not a multiple of 8, and the default border is 128×16),
  but both the hardcoded fallback in `options.lua` and the shipped enUS string kept
  saying 14px, so the slider tooltip lied to every user. Only the two strings that
  actually state a default needed changing — the other nine locales describe the
  slider without naming one.

- **Pawn made two guaranteed-to-fail calls per item when no scale was
  available.** `pawnLoadedScaleName` returns nil precisely when neither provider
  library has a scale for that class/spec, and that is exactly the state in which
  `GetItemScore` then built a guessed `"MrRobot":CLASSN`, called Pawn, failed, and
  built `"Classic":CLASSN` to call again: ~36 `pcall`ed calls per hover, all
  returning 0. It re-introduced the guessed-name pattern the helper exists to
  eliminate, and re-opened the `VgerCore.Fail` chat-spam path its own comment
  describes. `GetScore` now skips the call when there is no proven scale name.
  Behaviour-identical — both attempts already returned 0, and the tooltip gates on
  `pawnScore > 0`.

### Performance

Three allocation leaks on the tooltip hot path and one in the settings panel, all
of which the zero-allocation rule in `AGENTS.md` already forbids. Costs below are
measured in the offline harness, where the per-hover numbers are exact rather than
inferred.

- **`GetResolvedTooltipBorderEdgeSize` rebuilt and re-sorted the whole border list
  on every mouseover.** Its four sibling resolvers are memoised; this fifth one
  was not. It called `GetTooltipBorderChoices()` inside a `pcall` closure each
  time — allocating a `seen` table, 55 choice tables, 55 `string.format` preview
  strings, then sorting 55 entries. ~70 µs and ~110 allocations per hover, plus
  the closure. It also fired on every widget hover in the settings panel, because
  `showHoverTooltip` drives the real `GameTooltip`. The declared edge size is a
  property of the border *choice*, so it is now memoised against the resolved
  border path. The *config* fallback is deliberately never cached, which is what
  keeps the thickness slider live.

- **Every options interaction rebuilt and re-sorted all four media lists.**
  `panel.Refresh` on the Tooltips page called all four choice builders
  unconditionally; only the resolved *values* were memoised, never the lists.
  ~207 table allocations plus ~191 `string.format` per Refresh, fired by ~16
  different controls — a click or drag-release hitch. The lists are now memoised
  behind their own invalidation point, which meant splitting
  `InvalidateResolvedMediaCache` in two: an options interaction clears only the
  resolved values, while a SharedMedia registration still clears the lists.
  Handing out one shared instance is safe — `dropDown:SetValues` only replaces its
  reference, and `SetValue` and `toggleMediaPicker` only read.

- **One options refresh repositioned the overlays eight times.** The
  Character/Inspect page `Refresh` calls `setOffsetValue` eight times and each
  call ended in `refreshOverlayPositions()`, so one refresh cost 8 × (8
  `RefreshPosition` + a GearScore recompute). `TT:RefreshOptionsUI()` is what
  `CreateMover`'s `OnDragStop` calls, and those movers are parented to
  `PaperDollFrame`/`InspectFrame` — so the `IsShown()` guards passed exactly when
  the paper doll was open. **Releasing an overlay drag ran 8 full inventory walks
  (≈144 `GetItemInfo` calls) and 64 `SetPoint` calls** on the frame the player was
  waiting for. `setOffsetValue` takes a `silent` flag and the bulk refresh
  repositions once.

- **`TT:GetDefaults()` allocated a 60-key table per Tooltips-page refresh**, purely
  to read one field. The defaults are now a file-local `DEFAULTS` table shared by
  `SafeSanitizeConfig` and the Refresh. `GetDefaults()` hands out a **shallow
  copy**, because `resetCfg` assigns its result straight to `TacoTipConfig` and
  then writes `conf_version` into it — a shared table would let a reset mutate the
  defaults themselves. A regression assertion pins that.

- **The media texture lists are being pruned in a separate change**, not here. The
  audit of all 191 border and background entries (31 confirmed, 92 refuted, 68
  unverifiable) and the removal of the remaining fabricated paths land on their own
  so this performance work can be read, reverted and re-measured independently.

### Added

- **`/tt diag` now reports what an error handler structurally cannot.** BugSack
  and BugGrabger only ever see *raised* errors. The failures that cost the most
  time in this project were the opposite kind — no error, a plausible tooltip,
  and a feature quietly absent or pointed at the wrong thing. The diagnostic now
  prints a **PROBLEMS** section listing states where the addon is internally
  inconsistent: client detected as *both* Retail and WoW Forever or as *neither*
  (they share `WOW_PROJECT_MAINLINE`, so only the interface band separates them);
  a border setting that matches no entry, printing what it is being replaced by; a
  feature enabled while its backing API is absent; no unit delivery path hooked;
  and `GameTooltip.SetBackdrop` unexpectedly existing, which would silently
  activate the legacy full-backdrop branch. Read-only — it creates no widget and
  calls no setter.

- **`/tt diag` event counters**, cumulative since load: unit renders, GearScore
  callbacks split into re-entrant and wrong-unit, portrait hide, portrait
  destroy, portrait re-anchor. These exist because the portrait flicker was a
  question about how *often* code runs, and no amount of reading settles call
  frequency. Incremented inline on hot paths; cheap enough to leave in.

### Changed

- **`/tacotip reset` now resets appearance.** `resetCfg` replaced the whole config
  table and invalidated one dependent, but not the four memoised resolved media
  values, so the two reset paths disagreed: the reset **button** went on to call
  `RefreshOptionsUI` → `modernGetConfig` (which invalidated), while
  **`/tacotip reset`** only refreshed the root page. A player who picked a custom
  font, border, background or bar texture and typed `/tacotip reset` kept all four
  applied for the rest of the session. The invalidation now sits in `resetCfg`
  itself, at the choke point, rather than depending on which caller followed.

- **A test defect that made the portrait fix unprovable.** The harness's mock
  widget hardcoded `GetAlpha` to return 1, so the "portrait alpha is not slaved"
  assertion passed *unconditionally* — the slave copied 1, and 1 was the expected
  value. The first bite-check of that fix therefore failed to bite. `GetAlpha`
  now returns the widget's own `__alpha` and `SetAlpha` writes it, and both
  portrait bite-checks now fail correctly when reverted (Retail fails; Classic
  Era stays green through both).
- Three new modern-only assertions cover the portrait: alpha is 1 while the
  tooltip is at 0.25, anchored at most once across 5 re-renders, and no
  `OnUpdate` registered during re-renders. The last is asserted by instrumenting
  `SetScript` rather than reading `GetScript("OnUpdate")` back, because the mock
  `PlayerModel` carries the parent tooltip's whole script table and so reports
  Blizzard's template scripts rather than what the addon installed.

- **Nine assertions across `options_test` and `settings_test`**, all reverted to
  confirm they fail before being restored: the edge-size lookup builds the border
  list once instead of 52 times over 51 calls; the resolved value is still 32 for
  a themed border (so the count assertion cannot be satisfied by returning a
  constant); a fractional saved edge size floors to 16; `/tacotip reset`
  invalidates the media cache; one refresh repositions the overlays once instead
  of eight times; 50 refreshes rebuild none of the four media lists; the
  thickness slider disables itself for a border that carries its own size; no
  locale describes the thickness default as 14px; and `GetDefaults` still returns
  a fresh table.

  Three of these needed the harness corrected, and in all three cases the harness
  was wrong rather than the code:

  - **Counting calls cannot test a memo.** The first draft wrapped
    `GetTooltipBorderChoices` and incremented a counter — which reports 51 whether
    or not the memo works, because the call still happens either way. It now counts
    *distinct tables returned*, which is the rebuild count.
  - **A control assertion that could not fail.** The Pawn check needs to prove two
    things: that no Pawn call happens when no scale is available, and that the
    inventory *is* walked when one is. The second half failed for two wrong
    reasons before it meant anything. The registered scale was named
    `"MrRobot":WARRIOR1` while the mocked client resolves class `Warrior` and spec
    `3`, so nothing matched; and the `PawnGetSingleValueFromItem` stub returned
    three values where `pawn.lua` reads the **second** return, so every score read
    0 even once the name matched. Both were harness bugs — the stub had the wrong
    arity, and the control ignored the client's own resolution.
  - `settings_test` read the declared-settings list out of the `GetDefaults`
    source body. That body is now a six-line copy loop, so the sweep found no
    keys at all and reported `locale_override` as undeclared. It now reads the
    `DEFAULTS` literal instead. The intent of the block is unchanged.

### Known limitations

- **Retail and WoW Forever are under active in-game test as of 2026-10-10.**
  Classic Era, TBC Anniversary and WotLK Titanforge are confirmed working in a
  live client. The three fixes above are verified by reading, by the harness and
  by bite-check, but the Retail/Forever half of each still wants a live pass:
  the portrait holding still on a unit-frame hover, guild lines clearing on the
  next hover (the control the mock could not observe), and Baganator's tracked
  item amount surviving a hover.
- **`tooltip_background_texture`, its colour and its alpha are dead on all five
  clients.** `isBorderOnly` is set on every client that has a `NineSlice` child,
  which is all of them, and `SetBackdropColor` is gated on `not isBorderOnly`.
  The background dropdown still ships. This is a shipping decision — wire it to
  the NineSlice path or remove the controls — not a code defect to patch.
- **The Baganator line-ownership fix has no harness control.** The mock's tooltip
  lines read their text back as a table rather than a string, so ownership cannot
  be observed from the value. The "does not touch a line we no longer own" half
  is asserted; the "still clears our own line" half is not, and is carried as an
  in-game check.
- **`load_test.lua` still models the Classic family as having no `NineSlice`**,
  which the FrameXML contradicts, and pins that `Classic` keeps a legacy
  `SetBackdrop` fallback, which no client has. So the suite still cannot catch a
  Classic *border* regression, and every one of the 68 tooltip assertions runs
  the legacy branch no real client takes. **Downgraded from a release blocker**:
  the Classic family is confirmed working in a live client, so this is a test
  integrity note rather than a shipping risk. The `isBorderOnly` path still has
  no coverage on any client.
- Three advertised border choices are owned by **Details!** and so are unavailable
  to players who do not have that addon installed.

---

## [0.7.8] — 2026-09-29

> **This is the release that takes over the previous Classic-only TacoTip.** One
> addon, one version number, all five client families. `0.7.7` was never
> published.

### Fixed

- **The 3D portrait blinked while hovering a unit frame, on an unchanged
  character.** Reported in game as the portrait dropping and sliding back into
  frame roughly every half second, which is not how a genuine unit change
  behaves — and the same character blinking repeatedly is what identified it as
  a bug rather than the inherent cost of `PlayerModel`.

  **The model was never being reloaded.** `PlayerModel:SetUnit` loads a mesh
  asynchronously, so a genuine teardown-and-reload *would* be the obvious
  suspect, and the first fix went after it. That was wrong, and it is recorded
  here because the reasoning is the trap: the GUID-keyed cache on the portrait
  frame was working, `currentUnitGUID` was written once and never cleared, and
  for a same-character render nothing about the mesh needed to change.

  **What actually happened:** `Hide()` sat **outside** the destroy guard.

  ```lua
  if (tooltip.TacoTipPortrait3D) then
      tooltip.TacoTipPortrait3D:Hide()   -- ran for EVERY caller
      if (destroyModel) then ... end
  end
  ```

  A GearScore item load completes asynchronously and re-enters the whole tooltip
  pipeline through `TacoTip_GSCallback` → `GameTooltip:SetUnit` for the **same**
  character. `onTooltipSetUnit` correctly detected the unchanged GUID and asked
  to keep the model — but the frame was hidden regardless, and then re-shown by
  the next `ApplyTooltipAppearance`. The mesh never changed; the *frame* vanished
  and came back once per item that finished loading. With a `tooltip_delay` or
  the 0.05s border deferral in flight, the re-show lands after the hide, which is
  why it read as a drop and a slide rather than a flicker.

  **The fix:** `Hide()` moved inside the guard, and the third parameter was
  renamed `destroyModel` → `keepModel` so the default is the safe one — teardown.
  `onTooltipSetUnit` passes `(previousGUID ~= nil and previousGUID == guid)`,
  the same expression it already used, now meaning "keep" rather than "destroy".
  A same-unit re-render is now a complete no-op for the portrait.

  **A resident-model leak closed in the same pass.** Five call sites reach
  `clearTooltipVisuals` and only one passes the third argument, because only
  `onTooltipSetUnit` can compare GUIDs. The other four — `itemToolTipHook`, both
  non-unit branches of `onTooltipShow`, and a unit tooltip with no unit resolved
  — were hiding the frame while **keeping the model loaded**. Those are item,
  spell, quest and map-POI tooltips: there is no unit behind any of them, so a
  character model is meaningless and is now destroyed rather than left resident
  and merely invisible. A hidden frame still carries a loaded `PlayerModel`, and
  retained state is how this addon has bled one tooltip's visuals onto another.

  A genuine change of character still performs one asynchronous load. That brief
  blank on the first swap is inherent to `PlayerModel` and is **not** fixed here.

  **Two separate portrait defects are knowingly left in place**, since they are
  not the reported symptom and were not in scope: the portrait's alpha is still
  slaved to the tooltip's alpha in two places (once per render in
  `ApplyTooltipAppearance`, and continuously by the permanent 0.05s
  `onPortraitModelUpdate` poll), and the portrait is still re-anchored on every
  render via `ClearAllPoints()` + `SetPoint()` with its left/right side chosen by
  re-reading `tooltip:GetRight()` against screen width.

- **A stray specialization icon appeared on the wrong character** — the hovering
  player's own spec icon showing to the left of the tooltip on other people.
  Retail / WoW Forever only; the Classic family never used the overlay.

  Two independent causes, both fixed:

  1. **The library's icon lookup answered for the local player.** When the
     talent grid pass found nothing, `GetModernSpecializationIcon` fell back to
     `C_SpecializationInfo.GetSpecializationInfo(specIndex)` — called with **no
     unit argument**, so it always describes the *local* player. For anyone you
     have not inspected the grid pass always finds nothing, so the fallback
     always fired, which is why the stray icon showed up on other characters
     and looked reliable rather than intermittent. The fallback is now gated on
     `not isInspect`. An un-inspected unit correctly shows **no** icon rather
     than confidently showing the wrong player's.
  2. **The overlay was only cleared in one branch.** The clear sat in the `else`
     of the talent block, so a unit with no talent data never cleared it and
     the previous character's icon simply stayed on screen. The clear now runs
     first, unconditionally, in the talent block.

  A third, related defect: a miss for an inspect target was being written to the
  icon cache, which would have pinned "no icon" for the rest of the session and
  stopped the icon ever appearing, even after the target's talents streamed in.
  Misses for inspect targets are no longer cached, so the next hover re-queries.

  **Classic is provably unaffected.** `GetModernSpecializationIcon` opens with
  `if (not (isRetail or isForever)) then return nil end`, the Classic family
  never sets `useIconOverlay` so no overlay frame is ever created, and the
  Classic icon is inlined by `formatSpecializationText` from
  `GetLocalizedSpecIcon` — a different function this change never touches. A
  test now asserts the overlay frame is never created on a Classic client, which
  turns "should be safe" into "verified safe".

### Testing

A note on the earlier tests, because it is the general lesson: the pre-existing
portrait test drove the unit hook, which early-returns when the tooltip has no
text lines. That is true in the mock after the first render and never true in
game, so the hook path silently never reached the reload and the test passed
for the wrong reason. The tests here drive `ApplyTooltipAppearance` and
`clearTooltipVisuals` directly, which is what actually runs in a live client.

**The standing warning on this section.** A green harness did not mean the
portrait worked. The suite reported 50/50 while the portrait was visibly
blinking in game, twice, and the first fix was verified green while the blink
survived it. Nothing in a mocked environment can observe frame timing,
asynchronous model loads, or alpha interpolation. Treat the suite as necessary
and not sufficient: every portrait change is confirmed in a live client before
release.

Portrait tests, each verified to **fail** with the fix reverted rather than
merely passing:

- same-unit re-render through `ApplyTooltipAppearance` does not reload
- the same character via a *different* unit token does not reload (GUID-keyed)
- a real unit change *does* still reload
- **a non-unit tooltip tears the portrait down** — `ClearModel` runs and the
  frame is hidden, pinning the fix against a resident-model regression
- **`keepModel` does not destroy *or* hide** — the assertion that covers the
  actual defect. Reverting the fix fails it with `shown=false` on all five
  clients, which is the drop in isolation

The previous recycle test asserted the opposite contract — that a non-unit
recycle *preserves* the model — and had to be replaced rather than kept. It was
encoding the design mistake, so it passed while the portrait was still blinking.
That is the same failure mode this addon has hit before, and it is the reason
every one of these is reverted-to-fail before being accepted.

One test-harness bug worth recording: the new `keepModel` test initially failed
for the wrong reason. It zeroed its counter *before* calling
`ApplyTooltipAppearance`, which legitimately clears once after a teardown has
dropped the loaded-unit cache — so it was measuring the reload rather than the
recycle. The test was fixed, not the code.

A note on the earlier tests, because it is the general lesson: the pre-existing
portrait test drove the unit hook, which early-returns when the tooltip has no
text lines. That is true in the mock after the first render and never true in
game, so the hook path silently never reached the reload and the test passed
for the wrong reason. The tests here drive `ApplyTooltipAppearance` and
`clearTooltipVisuals` directly, which is what actually runs in a live client.

**The standing warning on this section.** A green harness did not mean the
portrait worked. The suite reported 50/50 while the portrait was visibly
blinking in game, twice, and the first fix was verified green while the blink
survived it. Nothing in a mocked environment can see frame timing, async model
loads, or alpha interpolation. Treat the suite as necessary and not sufficient:
every portrait change is confirmed in a live client before release.

Four specialization-icon assertions were added with the same discipline:

- an un-inspected target does **not** receive the local player's spec icon — the
  exact stray-icon defect, verified to fail with the fix reverted
- the local player's own icon still resolves, so the overlay still works for you
- a spec icon *does* appear once the target's talents are available, pinning the
  no-cache-on-miss behaviour
- the Classic family never creates the overlay frame at all

**This fix is incomplete and is not the whole stray-icon story.** The overlay
code was never reverted, so on Retail / WoW Forever the tooltip still draws
**two** icons for one specialization: the inline `|T` escape emitted by
`formatSpecializationText`, plus the overlay texture outside the tooltip's left
edge. The overlay was intended to *replace* the inline icon on modern — its own
comment says the Classic family keeps the icon inlined and modern does not — but
nothing ever suppressed the inline path, so modern draws both. Separately,
`hasDualSpec` is derived as `isWotlk or isTBC or (C_SpecializationInfo ~= nil)
or (GetNumTalentGroups ~= nil)`, and `C_SpecializationInfo` is not nil on
modern, so **a second spec line is rendered on clients that have one spec per
character**, each with its own inline icon. Both are still open and are the
likely cause of the "arms icon plus a second icon outside the edge" report.
Removing the overlay and correcting `hasDualSpec` for modern were scoped out of
this pass and have not been done.

### Corrected documentation

- **"Classic Era has no `NineSlice`" was false.** Classic Era *does* have a
  `NineSlice` child, reached by a different template chain rather than by its
  absence: `GameTooltip` inherits `GameTooltipTemplate`
  (`Blizzard_GameTooltip/Classic/GameTooltip.xml:13`), which inherits
  `GameTooltipCommonTemplate, TooltipBackdropTemplate`
  (`Blizzard_SharedXML/Classic/GameTooltipTemplate.xml:22`), and
  `TooltipBackdropTemplate` declares
  `<Frame parentKey="NineSlice" inherits="NineSlicePanelTemplate" useParentLevel="true"/>`
  at `Blizzard_SharedXML/SharedTooltipTemplates.xml:104-110`. WoW Forever and
  Retail reach the same child via `SharedTooltipTemplate` →
  `SharedTooltipArtTemplate` at `SharedTooltipTemplates.xml:19`. Only the
  `SetBackdrop` half of the original claim was correct: no supported client
  mixes `BackdropTemplateMixin` into the tooltip, so `GameTooltip.SetBackdrop`
  is nil on all five.
- **The two chains differ in a way that matters.** `GameTooltipTemplate` carries
  `mixin="GameTooltipMixin"` on the three Classic branches but
  `mixin="GameTooltipDataMixin"` on Forever and Retail, and only the Classic
  chain inherits `TooltipBackdropTemplate`. So the *tooltip itself* exposes
  `SetBackdropColor` / `SetBackdropBorderColor` on the Classic family but not
  on Forever or Retail. Border code must therefore never call those on the
  tooltip, and always writes to the `TacoTipBackdropFrame` overlay it creates
  from the `BackdropTemplate` template (`Blizzard_SharedXML/Backdrop.xml`,
  loaded by all five).

### Still outstanding

- **The stray specialization icon is only partly fixed — two causes remain**, as
  detailed above: the modern overlay was never removed, so it duplicates the
  inline icon, and `hasDualSpec` still claims dual spec on single-spec modern
  clients, adding a second spec line and a second icon.
- **The portrait's alpha is still slaved to the tooltip's alpha**, per render and
  via a permanent 0.05s `OnUpdate` poll, and the portrait is still re-anchored
  on every render. Both are separate defects, not the reported symptom, and were
  deliberately left alone.
- **`Tests/harness/load_test.lua` still models the Classic family as having no
  `NineSlice`** (lines 228, 248, 470), which the FrameXML contradicts — the
  Classic family reaches the same child through
  `GameTooltipTemplate` → `TooltipBackdropTemplate`, not by its absence. The
  suite therefore asserts a per-client contract that does not exist and **cannot
  catch a border regression on Classic**. This is the highest-priority follow-up
  before release.
- **The 3D portrait fix is unverified in a live client.** The static reasoning
  is solid and the tests bite, but frame timing, async model loads and alpha
  interpolation cannot be observed from a mocked environment — which is exactly
  how a green suite coexisted with a visible blink twice in this release.

### Critical

- **`GameTooltip:HookScript("OnTooltipSetUnit", ...)` was unguarded, and that
  raised at file scope on Retail.** `HookScript` errors with *bad argument #2 to
  'HookScript'* when the frame does not already declare that script. The Classic
  tooltip template declares `OnTooltipSetUnit`, `OnTooltipSetItem` and
  `OnTooltipSetSpell`; **Retail's does not** -- `SharedTooltipTemplate` on the
  live branch declares only `OnShow`, `OnHide`, `OnLoad`,
  `OnTooltipSetDefaultAnchor` and `OnTooltipCleared`. The old code hooked all three
  unconditionally, describing them as "registered as insurance ... the duplicate
  registration is inert". On Retail the insurance was not inert: it raised, and
  because `main.lua` is the **last** file in the toc, everything defined after that
  line never ran -- the item hooks, the visual clearing, the anchor hook, the
  overlays, and `TacoTip_CustomPosEnable`. That is the whole reported failure in
  one statement: the tooltip pipeline was dead, and the mover button said
  "not ready" because that function genuinely did not exist.
  Verified against `SharedTooltipTemplates.xml` on `live` and on all three Classic
  branches of `wow-ui-source`. All three hooks are now behind a `HasScript` guard,
  and `TT.HookedTooltipScripts` records which path each client ended up with
  (`postcall` on modern, the script hook on Classic).
- **`CreateFrame("Texture", nil, tooltip)` is not valid.** `Texture` is a *widget*
  type, created with `frame:CreateTexture()`; the real `CreateFrame` rejects it with
  *CreateFrame: Unknown frame type 'Texture'*. The specialisation-icon overlay used
  it, and that overlay is Retail/Forever-only (`useIconOverlay`), so the error fired
  on **every** unit tooltip on exactly the two clients that use it -- and because it
  happened inside the tooltip hook, it aborted the rest of the enhancement, so
  nothing at all was added. Classic never reached the line. Now
  `tooltip:CreateTexture(nil, "ARTWORK")`.
- **A `Texture` is a `Region`, not a `Frame`, on Retail and WoW Forever — so
  `SetFrameLevel` does not exist on it.** With the two defects above fixed the
  overlay got as far as its third line and then raised *attempt to call a nil
  value*, again on every unit tooltip and again aborting the rest of the
  enhancement. `SetSize` and `SetPoint`, on the two lines above it, are `Region`
  methods and worked; `SetFrameLevel` is a `Frame` method and the call is simply
  absent. On the Classic family a `Texture` does inherit `Frame`, so the call is
  valid there — which is why nothing in the codebase ever exercised the modern
  branch. Only `Texture` is affected: `Frame`, `Button` and `PlayerModel` are
  `Frame`s on every client, so the addon's other frame-level calls
  (`TacoTipPortrait3D`, `TacoTipBackdropFrame`, the mover and the drag button) are
  sound. The call is now guarded; on modern clients the texture keeps the
  `ARTWORK` draw layer `CreateTexture` already gave it, which is the Region-side
  equivalent. Swept every other texture and `FontString` in the addon for the
  same assumption — all of them use Region-level methods only.
- **`CharacterModelFrame` does not exist on Retail, and the character-pane
  GearScore / iLvl overlay indexed it unguarded.** The Classic family nests a
  `PlayerModel` named `CharacterModelFrame` inside `PaperDollFrame`
  (`Blizzard_CharacterFrame/{Vanilla,TBC,Wrath}/PaperDollFrame.xml`); Retail
  removed that model frame and keeps only `PaperDollFrame`
  (`Blizzard_UIPanels_Game/Mainline/PaperDollFrame.xml`) — there is no
  definition of `CharacterModelFrame` anywhere in the live FrameXML. Every
  character-pane refresh therefore raised *attempt to index global
  'CharacterModelFrame' (a nil value)*, and because `refreshOverlayPositions`
  calls `TT:RefreshCharacterFrame()` whenever `PaperDollFrame` is shown, **opening
  the options frame threw**. The font strings are now parented to
  `_G.CharacterModelFrame or _G.PaperDollFrame`, and both init and refresh return
  cleanly when neither exists. This makes the overlay *work* on Retail instead of
  only avoiding the crash; the startup guard was widened from
  `CharacterModelFrame and PaperDollFrame` to the resolved host, so the initial
  paint also runs there. Classic is unchanged — `CharacterModelFrame` exists and
  is still preferred. A sweep of every other Blizzard frame the addon touches
  (`PaperDollFrame`, `InspectFrame`, `InspectPaperDollFrame`, `InspectModelFrame`,
  `GameTooltipStatusBar`, `CharacterFrame`, `MerchantFrame`) found no further
  gaps: `GameTooltipStatusBar` is declared as `$parentStatusBar` in
  `GameTooltip.xml` and is already nil-guarded, and `RefreshInspectFrame` already
  guarded its own frames.
- **The 3D portrait was torn down and rebuilt on every asynchronous GearScore
  completion, so it visibly strobed.** This is the "something is not being reset
  and bleeding through" symptom, and it was neither re-entrancy nor a stale value.
  `itemcacheCB` fires `TacoTip_GSCallback` each time an item load *completes* —
  asynchronously, long after the drive that registered it returned, so no
  re-entrancy guard can see it. Each completion re-drove the tooltip for the
  **same** unit, and `clearTooltipVisuals` called `ClearModel()` on the
  `PlayerModel` every time, reloading it. A tooltip whose items are still
  streaming in therefore flickered for as long as loads kept arriving.
  `clearTooltipVisuals` now takes a `preserveModel` flag; `onTooltipSetUnit`
  resolves the unit's GUID *before* clearing so it can tell "the unit changed"
  from "the same unit is being re-rendered", and only the former tears the model
  down. Every other overlay still clears on every path. `tooltip_test` drives the
  same unit three times and asserts the model survives, then changes the unit and
  asserts it is cleared; reverting the guard reports `ClearModel calls=3`.
- **`TacoTip_GSCallback` could re-enter itself without bound, rebuilding the
  tooltip many times a second on a unit-frame hover.** `itemcacheCB` (and its
  Pawn twin) fire the callback once an item load completes; the callback re-drives
  the tooltip, which re-runs the whole pipeline — our unit post-call recomputes
  GearScore, which registers further item loads, which complete and call straight
  back in. Nothing bounded that nesting, so holding the mouse on a unit frame
  rebuilt the content endlessly: the tooltip appeared to reset over and over in
  the same spot, because the anchor never changed and only the content was being
  rebuilt. Re-entrancy is now guarded: a nested call for the guid already being
  serviced is satisfied by the call in progress and dropped, a nested call for a
  different guid is deferred and run once after unwinding, and the guard is
  cleared unconditionally through a `pcall` so a throw cannot leave it latched
  and silently kill every later callback. The non-nested case is unchanged.
  `tooltip_test` reproduces the loop by re-entering the callback from inside the
  drive: without the guard the pipeline is driven until the test's safety cap,
  with it exactly once.
- **A regression introduced while fixing the above: three Classic item tooltips
  stopped being hooked.** The first guarded version recorded the item hooks with a
  short-circuiting `or` chain over `GameTooltip`, `ShoppingTooltip1`,
  `ShoppingTooltip2` and `ItemRefTooltip`. On the Classic family `GameTooltip` is
  first *and* declares `OnTooltipSetItem`, so the chain stopped there and the
  other three were never hooked — a regression on the three clients that already
  worked, traded for a fix on the two that did not, and one that no diagnostic
  would have surfaced. `hookTooltipScripts` now attempts **every** frame in the
  list and records all successes, and `load_test` asserts each of the four by
  name on every Classic client; reintroducing the short-circuit now fails the
  harness on all three.
- **The harness used to invent `CharacterModelFrame` on every client**, including
  Retail, which is why an unguarded index of a frame that does not exist there
  passed. All four harnesses now blank it when the client is modern, matching the
  source; reverting the addon fix then fails Retail and WoW Forever and still
  passes TBC Anniversary.
- **`SetScript("OnRefresh"/"OnCommit"/"OnDefault", ...)` was wrong, and the game
  rejected it.** (Introduced earlier in this same pass, and caught before release —
  recorded here because the changelog should show what actually happened.) The Retail Settings panel invokes those three as **methods** --
  `frame:OnRefresh()`, `frame:OnDefault()`, `frame:OnCommit()` in
  `Blizzard_SettingsPanel.lua:8, :2, :557` -- and never `SetScript`s them; they are
  reserved canvas handler names, not script slots, so `SetScript` raises *bad
  argument #2 to 'SetScript'*. They are now assigned as function fields. The
  `OnShow` script is kept for the classic `InterfaceOptions_AddCategory` path, which
  has no such handlers.
- **Talent line was broken on the Classic family, confirmed in game.** On TBC Anniversary the tooltip rendered `Talents: Marksmanship [132164/132222/132215]` — those numbers are talent *icon* fileIDs, not points — with no talent icon, and only one specialization instead of two. Three separate causes, all in the library: the port introduced a `getTalentTabPoints` helper that read the wrong `pcall` return slots and captured `icon` as `pointsSpent`; the `|T` escape required a `string` and so dropped every numeric fileID; and the `hasDualSpec` gate was never ported. Because the points were garbage, both groups resolved to the same tab and the `spec2 ~= spec1` guard hid the second line entirely. All three are fixed and the Classic path now uses the known-good algorithm from the root addon — see [Talents and specializations](#talents-and-specializations).
- **Removed the duplicate `.toc`.** A second, byte-identical toc file shipped alongside the real one. WoW loads *every* `.toc` in an addon folder, so all 16 files executed twice on every client: tooltip hooks double-registered, lines duplicated, and `local addOnName = ...` split the `_G.TT` namespace in two. There is now exactly one toc, and it is named to match the folder it ships in.
- **Corrected `## Interface:` for Titanforge.** Titanforge is `3.80.2` → interface `38002`; the toc listed `38001` (3.80.1), so the addon did not load there at all. Also dropped the dead `110005` / `110007` entries and the README's deprecated `30405`.
- **Fixed tooltip hooks that registered but never fired on TBC Anniversary and Titanforge.** Both clients define `TooltipDataProcessor` and `Enum.TooltipDataType`, so the old presence-only test took the modern branch — but their `GameTooltip` mixes in `GameTooltipMixin` alone, never `TooltipDataHandlerMixin`, so `ProcessTooltipPostCalls` was never reached. Both clients showed stock Blizzard tooltips: no GearScore, spec lines, guild reformat, class colours, 3D portrait, power bar, or item iLvl / HunterScore. Hook selection now probes `IsTooltipType` / `GetPrimaryTooltipData` (which come from the mixin itself), and both paths are registered as insurance.
- **Locale: German was dead, and the language override never applied.** Nine locale files had a `GetLocale()` guard and bound `_G.TACOTIP_LOCALE`; `deDE` alone had been converted to the `TACOTIP_LOCALES` registry, which nothing reads, so German clients silently got English. All eleven now register into `TACOTIP_LOCALES` and `enUS.lua` is the single selector, re-applied on `ADDON_LOADED` — addon files run before WoW populates `SavedVariables`, so `locale_override` was unreadable at file scope. `TacoTipApplyLocale` mutates the table in place so the `local L` bindings in `main.lua` / `gearscore.lua` / `options.lua` observe the change. `enGB` maps onto `enUS`.

### Tooltip rendering
- **`BackdropTemplateMixin` was grafted onto the live `GameTooltip` on exactly the two clients that must not have had it.** The early fallback tested `not GameTooltip.SetBackdrop` to decide whether the tooltip needed the legacy backdrop mixin. That is the wrong signal. Retail and WoW Forever use `SharedTooltipArtTemplate`, which attaches a `NineSlice` child and does **not** mix in `BackdropTemplateMixin` — so `GameTooltip.SetBackdrop` is nil there even though the tooltip renders perfectly. The test therefore fired on Retail and Forever and installed 16 unused `backdropInfo`-based methods (`SetBackdrop`, `SetBackdropColor`, `SetBackdropBorderColor`, `ApplyBackdrop`, `ClearBackdrop`, …) onto the real tooltip, overriding the `NineSlice`-driven rendering the appearance code depends on. The condition now requires the **absence of `NineSlice`**, which is what the surrounding comment always said it meant, and which leaves the Classic family byte-identical: **Correction — Classic Era does have a `NineSlice` child.** It is reached by a different template chain than Retail's, not by its absence: `GameTooltip` inherits `GameTooltipTemplate` (`Blizzard_GameTooltip/Classic/GameTooltip.xml:13`), which inherits `GameTooltipCommonTemplate, TooltipBackdropTemplate` (`Blizzard_SharedXML/Classic/GameTooltipTemplate.xml:22`), and `TooltipBackdropTemplate` declares `<Frame parentKey="NineSlice" inherits="NineSlicePanelTemplate" useParentLevel="true"/>` at `Blizzard_SharedXML/SharedTooltipTemplates.xml:104-110`. WoW Forever and Retail reach the same child through `SharedTooltipTemplate` → `SharedTooltipArtTemplate` at `SharedTooltipTemplates.xml:19`. So the `not NineSlice` guard does not fire on Classic either, and the Classic family was **not** left relying on a legacy `SetBackdrop` fallback. Only the `SetBackdrop` half of the original claim was right: no supported client mixes `BackdropTemplateMixin` into the tooltip, so `GameTooltip.SetBackdrop` is nil on all five. The two chains differ in one further way worth recording — `GameTooltipTemplate` carries `mixin="GameTooltipMixin"` on the three Classic branches but `mixin="GameTooltipDataMixin"` on Forever and Retail, and only the Classic chain inherits `TooltipBackdropTemplate`, so the tooltip itself exposes `SetBackdropColor` / `SetBackdropBorderColor` on the Classic family but not on Forever or Retail. That asymmetry is why the border code must never call those methods on the tooltip and instead always writes to the `TacoTipBackdropFrame` overlay it creates itself with the `BackdropTemplate` template (`Blizzard_SharedXML/Backdrop.xml`, loaded by all five).
  - Verified against `Blizzard_SharedXML/SharedTooltipTemplates.xml` and `Backdrop.lua` on the `live` branch and the `classic_era` branch of `wow-ui-source`.
  - The offline harness could not see this at all: its mock hands **every** widget **every** method, so `GameTooltip.SetBackdrop` was always a function and the guard was never taken on any client.
  - **Correction — `load_test` does not model the real Classic template, and its "pins the contract both ways" claim is wrong.** It still asserts the Classic family has no `NineSlice` (`Tests/harness/load_test.lua:228`, `:248`, `:470`), which the FrameXML above contradicts. The guard therefore cannot fire on the Classic family in the harness either, but for a reason the mock gets wrong rather than right. The assertions are documented here as unverified against the real Classic template; correcting the mock is outstanding and is **not** done in this entry.



- **`CreateFrame("Texture", ...)` is not a valid call.** `Texture` is a *widget*
  type, created with `frame:CreateTexture()`; the real `CreateFrame` rejects the
  frame-type form with *CreateFrame: Unknown frame type 'Texture'*. Now
  `tooltip:CreateTexture(nil, "ARTWORK")`. See
  [Critical](#critical) for why this alone took out the whole Retail tooltip.

### Talents and specializations

- **Talent points on the Classic family were reading the wrong return value, and printed icon fileIDs as numbers.** The tooltip showed `[132164/132222/132215]` — those are talent *icon* fileIDs. The cause was a `getTalentTabPoints` helper introduced by this port that read the wrong slots out of `pcall`'s results: `pcall` prepends a boolean, so every position is shifted by one and the `icon` field landed in `pointsSpent`. That helper is **removed**. `LibForeverInspector` now computes Classic talent points the way the working `LibClassicInspector` does, by summing each talent's `rank`:
  `talents[tab] += select(5, GetTalentInfo(tab, talent, isInspect, isPet, group))`
  which is the same total `pointsSpent` reports, but is stable whether or not the `loadDeprecationFallbacks` CVar is set.
- **The specialization icon on the Classic family never rendered.** `main.lua` resolves it with `CI:GetTalentInfoByClass` — unchanged working code — but `LibForeverInspector` is a rewrite of `LibClassicInspector` and the rewrite dropped both `GetTalentInfoByClass` and the ~1840-entry static `talents_table` it reads. With the callee nil, `pcall` always failed and the lookup returned nil. The icon is **not** read from a live API on Classic; it comes from that static table. The table, `GetTalentInfoByClass`, `GetNumTalentsByClass` and the WotLK glyph data are ported verbatim. Per expansion: Classic Era 18 talents in Warrior tab 1 (Vanilla), TBC Anniversary 23 (TBC), Titanforge 31 (WotLK, Death Knight included) — each resolving real icon textures.
- **The `|T` icon escape dropped every fileID.** `formatSpecializationText` required `type(icon) == "string"` before inlining the icon, but the static table returns a *number*, so no icon ever appeared. The working addon formats it with `tostring()`, because a `|T` escape accepts a fileID as well as a texture path. Restored.
- **Dual specialization is now available on Classic Era, TBC Anniversary and Titanforge.** The `hasDualSpec` gate from the working library was never ported, so group 2 was attempted on every client without support. It is now defined identically (`isWotlk or isTBC or (C_SpecializationInfo ~= nil) or (_G.GetNumTalentGroups ~= nil)`, read through `_G` so it is nil-safe) and `GetSpecialization` / `GetTalentPoints` refuse group 2 where it is false. The wrong point values had also been making both groups resolve to the same tab, so the `spec2 ~= spec1` guard suppressed the second line entirely.
- **The inspect cache only ever held group 1.** `cacheUnitData` hardcoded group 1 (`getTalentTabPoints(t, true, false, 1)`), so inspecting a dual-spec'd player returned group 1's data for group 2 as well. It now builds `talentPoints[group][tab]` and `specIndexByGroup[group]` for every supported group.
- **`GetActiveTalentGroup` returned 1 for every inspected unit**, so the tooltip always coloured group 1 and greyed group 2 regardless of which group the inspected player was actually on. It now reads `GetActiveSpecGroupFor(true)` into `data.activeGroup` and returns that, so the greyed specialization is genuinely the inactive one.
- **Retail and WoW Forever now show talent points.** Neither has `GetNumTalentTabs`, so the talent-tab path cannot run there and `GetTalentPoints` returned `0/0/0`. `C_SpecializationInfo.GetSpecializationInfo` has the same 7-argument signature and 10-value return on all five clients, with `pointsSpent` at 7 and `previewPointsSpent` at 9, so per-specialization points are read from it.
- **The modern path is now group-aware.** It used `GetSpecialization()` for self and `GetInspectSpecialization(unit)` for others; the latter takes only a unit and so cannot distinguish group 1 from group 2. It now calls `GetSpecialization(isInspect, isPet, groupIndex, 1)`, the only group-aware form, with both old calls kept as fallbacks.
- **`GetSpecialization` returned a specID where callers expected a spec index** — an ID such as `72` where every consumer indexes `lib.spec_table[class][specIndex]`, so `spec_table.WARRIOR[72]` was nil and the whole specialization line silently disappeared on Retail and WoW Forever. It now returns the 1-based index.
- **Specialization icons on Retail and WoW Forever** come from `CI:GetModernSpecializationIcon` via `C_SpecializationInfo.GetTalentInfo`. The **query form** differs by FrameXML toc: Classic Era / TBC / Titanforge load `Vanilla\TalentFrameBase.lua` and query by `specializationIndex` + `talentIndex`, while Retail and WoW Forever load `[Family]\TalentFrameBase.lua` and query by `tier` + `column`. The modern resolver uses tier/column, falls back to linear, and is gated to Retail/Forever so Classic is untouched. `TalentInfoResult.icon` is a fileID, which `|T` cannot render, so it is drawn with a `Texture` overlay that is only created when there is an icon to draw.
- **Specialization names follow the client's language on Retail and WoW Forever** via `CI:GetLocalizedSpecName` / `CI:GetLocalizedSpecIcon`, resolved per spec group so the two dual-spec lines do not both wear group 1's name. The Classic family still uses the built-in table.
- `GetModernSpecializationIcon` is deliberately *not* named `GetSpecializationIcon`: the latter is a pre-existing stub in this library that always returns nil, and the two definitions silently overwrote each other.

### GearScore

- **WoW Forever now uses the 200 bracket.** It is a Classic-like client (level cap 60, no level scaling) but had no branch and inherited the 1000 default, inflating every score 5x and collapsing the whole colour ramp into the "Common" white band. No formula or colour change — the bracket is a pure mapping, so the Classic ramp and the iLvl average are preserved.
- Test no longer asserts against a hardcoded `GetQuality(7000)`; it uses `GS.MAX_SCORE`, and now also asserts the bracket agrees with the detected family.

### Client detection

- Rebuilt around `WOW_PROJECT_ID` (distinct per Classic client: 2 / 5 / 11) with the interface version used only to separate WoW Forever from Retail, which both report `WOW_PROJECT_MAINLINE`. The previous code derived everything from `select(4, GetBuildInfo())`, whose return layout is documented only for Retail and Forever.
- The interface number is now read from whichever `GetBuildInfo()` return slot is numeric, so detection does not depend on the unverified Classic layout. Covered by tests under both layouts.
- Added `CI.family`, `CI.IsUnknown()` and a `CI.caps` capability snapshot. An unrecognised client now resolves to `family == "unknown"` instead of silently inheriting a default — Cata and Mists previously matched no flag at all.
- `GetTalentTabInfo` / `GetNumTalentTabs` are no longer captured into file-scope locals. `GetTalentTabInfo` is a `loadDeprecationFallbacks`-gated deprecation shim, so a local latched to `nil` could never recover.
- Talent points now sum `pointsSpent + previewPointsSpent`, matching Blizzard's own `TalentFrameBase_Shared.lua`; reading only the former under-reported after a respec and could select the wrong specialisation tab.
- `pcall` added around `C_SpecializationInfo.GetInspectSpecialization` (Retail flags it secret-restricted) and `GetSpecializationInfoByID`; a throw previously aborted `cacheUnitData` before it fired `INVENTORY_READY` / `TALENTS_READY`.
- Removed the dead `_G.TACOTIP_SPEC_NAMES` / `_G.TACOTIP_SPEC_ICONS` lookups from `main.lua` and `LibForeverInspector`. Nothing ever wrote those globals, so they were always nil and specialization names always came from the library's built-in table — while the surrounding comments claimed they followed the language override. `GetSpecializationIcon` is kept as a stub that honestly reports it has no override to return.
- `NotifyInspect` is now guarded, matching its `CanInspect` / `ClearInspectPlayer` siblings.
- The `LibClassicInspector` alias is registered unconditionally and now carries a minor version, so a version bump re-points it instead of leaving callers on a stale table.

### Localization

- **English is now the explicit default, with WotLK Titanforge pinned to Simplified Chinese.** Resolution order is: `TacoTipConfig.locale_override` (always wins) → Titanforge → `zhCN` → the client language when a table is shipped for it → English. Titanforge is the Chinese build of WotLK, so its default is no longer whatever `GetLocale()` happens to report; English is both the default and the per-key fallback every other language is layered over. The other four clients still follow the client language as before.

### Tooltip mover handle

- **The green drag handle now starts on the tooltip's top-left corner, with the
  tooltip still in the bottom-left of the screen.** The handle's default screen
  position was the **bottom-right** corner, so on a fresh profile the handle
  rendered at the far end of the tooltip from the name — level with the
  "Drag to Move" instruction line — which is the opposite end from where you
  naturally grab it. The default is now `BOTTOMLEFT` of the screen, and it pairs
  with the existing `custom_anchor` default of `TOPLEFT`: the tooltip's TOPLEFT is
  pinned to the handle's TOPLEFT, so with the handle's BOTTOMLEFT on the screen's
  BOTTOMLEFT the tooltip occupies the strip directly above it. Both halves are
  pinned by `load_test` — through `TacoTip_CustomPosEnable` and
  `TT:SyncTooltipMover`, the real path rather than the local default function —
  and the test also proves a **saved** `custom_pos` is still honoured, which would
  otherwise be silently broken by changing the default. Reverting the default
  reports `got BOTTOMRIGHT/0/0`. Existing installs keep their saved position;
  *Reset* on the mover clears `custom_pos` and picks up the new default.

### Chat spam from the tooltip pipeline

- **Root cause of the repeated `ScaleName must be the name of an existing scale,
  and is case-sensitive.` — the Pawn scale library name does not follow the client,
  and the fix that looked safe could not work.**
  Pawn ships exactly two scale providers and `Pawn.toc` gates them by game type, so
  exactly one exists on any given client:

  | Provider file | `AllowLoadGameType` | Clients | Library name |
  | :--- | :--- | :--- | :--- |
  | `AskMrRobot.lua` | `mainline` | Retail, WoW Forever | `"MrRobot"` |
  | `ClassicHawsJon.lua` | `classic` | Vanilla, TBC, Wrath | `"Classic"` |

  The shipped code preferred `"MrRobot":CLASS..SPEC` and then asked
  `_G.PawnIsScaleVisible` whether that scale existed, falling back to `"Classic"`.
  On the **Classic family** that probe asked about a library Pawn does not have
  (`AskMrRobot.lua` is not loaded there), and on **Retail / WoW Forever** the
  fallback was never needed. That is the original report.

  Two facts about Pawn make this unfixable by probing, and both were verified in
  the installed `Pawn/` sources rather than assumed:

  1. `PawnIsScaleVisible` and `PawnGetScaleColor` report an unknown name through
     `VgerCore.Fail`, and **`VgerCore.Fail` does not raise a Lua error** —
     `VgerCore/VgerCore.lua:160` calls `VgerCore.Message`, which writes straight to
     `DEFAULT_CHAT_FRAME:AddMessage`. **`pcall` cannot suppress it.** So the old
     "probe, then fall back" logic printed one chat line per player tooltip render
     and per unit frame refresh *no matter how it was guarded*, which is why an
     earlier attempt that only wrapped the probe in `pcall` did not fix it.
  2. The scale name is `<CLASSNAME><specIndex>` — `Pawn.lua:5784` builds
     `ScaleInternalName = UnlocalizedClassName .. (SpecID or "")` — and
     `PawnGetScaleColor` looks the whole name up in the global `PawnCommon.Scales`.

  `PawnScaleProviders` and `PawnCommon` are both plain globals, so the same
  question is answered by **reading Pawn's own registries**, which is completely
  silent. `pawn.lua` now resolves the library from the provider Pawn actually
  registered *and* the scale actually present in `PawnCommon.Scales`, and calls
  `PawnGetScaleColor` only with a name proven to exist there — so the
  `VgerCore.Fail` branch is unreachable by construction. When nothing matches
  (Pawn still initialising, or no scale for that class/spec) the colour is simply
  skipped, which is cosmetic. `PawnIsScaleVisible` is no longer called at all.
- **The deferred Pawn readiness probe was itself a source of the spam and is
  gone.** It called `PawnGetScaleColor("\"Classic\":ROGUE1", true)` blindly, which
  on Retail — where Pawn has no `"Classic"` library at all — printed the ScaleName
  error to chat by itself, once at 3s and again at 8s. A prior revision of this
  fix "restored" a 3s/5s version of that probe from the Classic build, which
  carried the defect over with it; the silent registry lookup subsumes it
  entirely, so there is now no timer, no `_TacoTipPawnReady` flag, and no call to
  Pawn before its scales are known to exist. `PawnGetSingleValueFromItem` — which
  *never* calls `VgerCore.Fail`, it just answers `0` for an unknown name — is
  still free to try both libraries, so the score itself works on every client.
- **`safeCall` was printing every pipeline error to the chat frame.** It used
  `xpcall(fn, geterrorhandler(), ...)`, and `geterrorhandler()` *is* the chat
  reporter. A single C API argument error carries no Lua stack, so BugSack showed
  it with no trace — and because the pipeline runs many times a second on a unit
  frame, the same message was reprinted endlessly and buried the chat. The
  default handler still runs, but only **once per distinct message per session**,
  so a real defect stays visible and a per-frame repeat does not. The most recent
  message is recorded on `TT.lastTooltipError` and reported by `/tacotip diag`,
  which is the only way to identify an error that has no stack.
- **Every string-taking C call in the render path now names itself.** A C API
  argument error arrives with nothing identifying which call produced it, which
  forces a bisect through the whole pipeline. `callLabeled` re-raises with the
  call site attached, and is used for `SetFont` on tooltip lines, `SetBackdrop`
  on the backdrop frame, and `SetStatusBarTexture` on the health and power bars —
  so the single reported message now names the exact call instead of leaving a
  guess. This instrumentation is defence in depth, not the fix: an exhaustive
  sweep of every file including the bundled libraries confirms the addon calls
  `SetScale` nowhere, which is what first ruled out a widget scale and pointed at
  Pawn's own scale-name API above.

### Settings and options
- **Every one of the 66 settings is now verified reachable, bound, persistent and
  resettable** — see [Testing](#testing). The Classic options UI is otherwise
  unchanged.
- **The Retail Settings canvas handlers are methods, not scripts.** The panel calls
  `frame:OnRefresh()`, `frame:OnDefault()` and `frame:OnCommit()` directly
  (`Blizzard_SettingsPanel.lua:8, :2, :557`) and never `SetScript`s them; they are
  reserved canvas-handler names, not script slots, so `SetScript` on them raises
  *bad argument #2 to 'SetScript'*. They are assigned as function fields, with
  `OnShow` retained for the classic `InterfaceOptions_AddCategory` path, which has
  no such handlers.

### Crash and correctness fixes

- `main.lua` `onTooltipSetUnit` called `tooltip:GetUnit()` unguarded on its first line; on clients where that method is a shim over a namespace that may not be loaded, the throw was swallowed by the surrounding `safeCall` and silently dropped the entire unit tooltip. Now `pcall`ed. Same fix in `options.lua`'s Power Bar handler.
- `GetQuestDifficultyColor` was cached at file scope. On the Classic family it is a Lua global from a `LoadFirst` Blizzard addon, and TacoTip declares no `LoadFirst`, so it could latch `nil` for the session and permanently disable hostile level colouring. Now resolved per call.
- `IsEquippableItem` was called as a bare global. It is created by `Blizzard_DeprecatedItemScript`, which early-returns unless the `loadDeprecationFallbacks` CVar is set — with it off, every item hover raised and lost its iLvl / GearScore lines. Now prefers `C_Item.IsEquippableItem`.
- `resolveTooltipUnit` returned `"mouseover"` unconditionally as a last resort. On the four clients without `TooltipUtil` that is the only fallback, so a stale `GetUnit()` painted the wrong unit's colour, portrait and GearScore onto e.g. the target tooltip. Now only accepted when the tooltip genuinely is the mouseover tooltip. The `data.guid` fallback is likewise limited to `mouseover` / `target`: mapping an arbitrary GUID onto a unit token would be a guess, and declining leaves the tooltip untouched rather than mis-attributed.
- `tooltip_max_width` was a silent no-op on every client: `GameTooltip` has no `SetMaximumWidth` anywhere (on all five branches it belongs only to `BaseMenuDescriptionMixin` and Calendar). Reimplemented by capping the line `FontString` widths, which wraps long content while leaving short lines untouched.
- `registerTooltipVisualClearing` iterated with `ipairs` over a table containing guaranteed `nil`s, so every frame after the first hole silently lost its hooks. Now `pairs`.
- `UnitIsSameServer` is guarded, matching its neighbours.
- `wipe(...)` → `table.wipe(...)` (confirmed present on all five clients); the bare global is protected on 10.0+.
- Options: slider `Text` / `Low` / `High` lookups now fall back to `CreateFontString`, matching the checkbox builder — a miss previously aborted the whole page build into a silently blank options page. ColorPicker legacy fallback sets `swatchFunc` (what `ColorPickerFrame.xml` actually reads) instead of `func`. `LoadAddOn` list includes the real Classic addon names. Removed a duplicated `InterfaceOptionsFrame_OpenToCategory` call.
- `textures.lua`: CJK fonts are hidden on non-CJK clients (they silently fell back to the default font) and third-party Details fonts are dropped from the "Blizzard -" list. Media lists are filtered per client.
- `scheduleItemTooltipRefresh`'s no-object-API fallback called `RequestLoadItemDataByID` as a **bare global**. There is no such global on any of the five clients — the only real form is `C_Item.RequestLoadItemDataByID` (confirmed against `Blizzard_ObjectAPI` on every branch) — so the branch silently did nothing. It now uses the file-scope local that already resolves the namespaced form.
- Removed the `C_Item.GetItemLinkByID(data.id)` arm from `resolveTooltipItem`. It has **zero** call sites on any client, and there is no replacement: `C_Item.GetItemLink` takes an `ItemLocation`, not a bare itemID. The `data.hyperlink` arm above it is what the post-call actually supplies, so item resolution is unaffected.
- The item-wrapper fallback in `LibForeverInspector.createItemWrapper` implemented only `ContinueOnItemLoad`, but `main.lua` calls `ContinueWithCancelOnItemLoad`. A safety-net object that does not honour the interface of the object it stands in for is worse than none, so the wrapper now implements the cancelable form. The call site additionally falls back to the non-cancelable variant rather than dropping the repaint entirely. (The real `ItemMixin` provides `ContinueWithCancelOnItemLoad` on all five branches, so this only affected the fallback path.)
- `main.lua`'s `itemLoadCancel` field doc named `C_Item.ContinueWithCancelOnItemLoad`, which is not a `C_Item` function at all — it is an `ItemMixin` method. Corrected.

### Retail / Forever file-scope robustness

A Lua error at file scope in `main.lua` does not just disable one feature: it
disables everything defined after that line, because the rest of the chunk never
runs. Two file-scope operations depended on a global existing, and neither was
guarded.

- **`hooksecurefunc("GameTooltip_SetDefaultAnchor", ...)` was unguarded.**
  `hooksecurefunc` raises "attempt to hook a non-existent function" when its
  target is absent, and this call sits at file scope, so the whole addon would
  abort. The target *is* present on all five clients -- it is defined by
  `Blizzard_SharedXML/SharedTooltipTemplates.lua`, and that addon is not
  LoadOnDemand -- so this is hardening, not a fix. The hook is now a named
  function installed behind a `type(...) == "function"` test, and records
  `TT.HookedDefaultAnchor` so the diagnostic can report it. When the target is
  missing, only the spell-tooltip anchor side selection is lost; every other
  anchoring path is untouched.

- **Retail's Settings panel contract is now honoured in full.** The panel drives
  canvas pages through three optional frame handlers: `OnRefresh` when the panel
  is shown, `OnDefault` on restore-defaults, `OnCommit` on Apply. The addon only
  used `OnShow`, which fires when the canvas frame becomes visible -- but the
  panel owns that visibility and reuses an already-shown frame, so a page can be
  re-selected without `OnShow` ever firing and the controls keep showing stale
  values. All three are now implemented; see
  [Settings and options](#settings-and-options) for the method-vs-script detail,
  which cost one iteration to get right.

### Retail / Forever API audit

Every Blizzard global, frame method, event name and frame template the addon
touches was cross-checked against the `live` (12.1.0.69814) and `classic_era`
branches of `wow-ui-source`:

- **Event names** — all 10 (`ADDON_LOADED`, `INSPECT_READY`, `MODIFIER_STATE_CHANGED`,
  `PLAYER_EQUIPMENT_CHANGED`, `PLAYER_LOGIN`, `UNIT_DISPLAYPOWER`, `UNIT_MAXPOWER`,
  `UNIT_POWER_UPDATE`, `UNIT_TARGET`, `UPDATE_MOUSEOVER_UNIT`) are documented on
  live. An unknown event raises at `RegisterEvent`, so this mattered.
- **Frame templates** — all 8 (`InputBoxTemplate`, `InterfaceOptionsCheckButtonTemplate`,
  `OptionsSliderTemplate`, `UIDropDownMenuTemplate`, `UIPanelButtonTemplate`,
  `UIPanelCloseButton`, `UIPanelScrollFrameTemplate`, `BackdropTemplate`) are
  defined in live XML. An unknown template is a hard error in `CreateFrame`.
- **Namespaced-away APIs** — `GetActiveTalentGroup`, `GetSpecializationName` and
  `CUSTOM_CLASS_COLORS` are no longer called bare by Blizzard on live, and the
  library does not call them bare either: `GetActiveSpecGroupFor` prefers
  `C_SpecializationInfo.GetActiveSpecGroup` with a `_G.GetActiveTalentGroup`
  fallback, `lib:GetSpecializationName` reads only the built-in table, and the
  class-colour lookup is nil-guarded. All safe.
- **Secret-argument-gated APIs** — `SetTexture`, `SetAtlas`, `SetColorTexture`,
  `SetVertexColor`, `SetText`, `SetFormattedText`, `GetItemInfo`,
  `GetItemInfoInstant` and `SetClampedToScreen` are `AllowedWhenUntainted` on
  live. Every call site passes either a literal or a value from the addon's own
  tables, except the talent-icon `SetTexture`, which was already `pcall`-wrapped.
- **One correction to an earlier claim.** An intermediate sweep reported
  `main.lua`'s bare `GetItemInfo(itemLink)` as a Retail failure, on the grounds
  that Blizzard never calls it bare. That reasoning was wrong: the generated
  `ItemDocumentation.lua` documents `GetItemInfo`, `GetItemInfoInstant` and
  `IsEquippableItem` as **globals** with no enclosing namespace, and FrameXML
  cannot witness engine globals at all -- only FrameXML-defined ones. The bare
  global does exist. The call site is now resolved namespace-first and
  nil-guarded like the one in `gearscore.lua`, so a client exposing neither form
  degrades instead of aborting the hook, but this is hardening, not a fix.

### Load diagnostics

- **A single error in `main.lua` silently disabled the mover, the tooltip pipeline and the overlays, and the UI blamed `/reload`.** `main.lua` is the last file in the toc and ~2900 lines long, and it defines `TacoTip_CustomPosEnable` at the very end. `options.lua`, `gearscore.lua` and `main.lua` itself all call that global. If anything raised at file scope, every one of those call sites took its fallback branch — and the mover's message was *"Tooltip mover is not ready yet. Try /reload."* That advice cannot help, because the cause is a load-time error, not a timing one. This is the signature of the reported Retail failure, and it is now diagnosable instead of guessable:
  - `main.lua` records `TT.LOAD_STAGE` at nine points through its own load and sets `TT.LOAD_OK` at the end.
  - **`/tacotip diag`** prints the version, whether the load completed, the last stage reached, the detected family and interface, and the type of each key global (`TacoTip_CustomPosEnable`, `TT.ApplyTooltipAppearance`, `TT.OpenOptionsPanel`, `TT.RefreshOptionsUI`, `TT.SyncTooltipMover`) plus the GearScore bracket and active locale.
  - The mover's own message now names the stage reached instead of advising a reload that cannot help.
  - `/tacotip diag` also reports which widget surface the client presents — `NineSlice`, `SetBackdrop` and `HasScript("OnTooltipSetUnit")` — because those three facts select the tooltip code paths. Reporting them makes "looks wrong on client X" answerable without guesswork, and the reporting is read-only: running the diagnostic creates no widgets.
  - New in-game `Client:LoadCompleted` and `Client:BackdropTemplateContract` tests, and matching `load_test` assertions for all five clients, so a partial load can never again be invisible offline.

### Testing

- Test suite moved to `Tests/` with its own toc and removed from the shipping toc. A second toc in the addon root would have re-created the double-load.
- New `TacoTip-Client` in-game suite covering detection, flag exclusivity, the legacy alias, the locale registry, override handling and font filtering.
- New `Tests/harness/` — plain-Lua harnesses that load the real addon against a mocked environment, needing no game client: `detect_test.lua`, `locale_test.lua`, `font_test.lua`, `load_test.lua`, `options_test.lua`, `settings_test.lua`, `tooltip_test.lua`.
- New `Tests/harness/run_all.sh` runs the entire matrix in one command — **50 invocations** across all five clients, both `GetBuildInfo` slot layouts, both settings-registration paths, both Pawn states, and two permutations that blank a Blizzard global to prove the file-scope hooks are guarded rather than fatal. It prints the failing invocation names and exits non-zero, so "all harnesses pass" is a single command rather than a list to remember.
- `options_test.lua` builds all four options pages and exercises `RefreshOptionsUI` / `OpenOptionsPanel` on every client **and** every capability permutation: with and without the `Settings` namespace (modern vs legacy `InterfaceOptions_AddCategory` path), without `ColorPickerFrame`, and without LibSharedMedia — including the worst case with all three absent.
- `tooltip_test.lua` asserts the enhancement pipeline actually produces output — GearScore, iLvl and specialization lines for self, other player, hostile NPC and items — across both delivery paths: the `OnTooltipSetUnit` / `OnTooltipSetItem` script hooks used on the Classic family, and the `TooltipDataProcessor` post-calls used on Retail and WoW Forever, including the `data.guid` resolution branch.
- The in-game suite previously drove only the legacy `OnTooltipSetUnit` script path; the `TooltipDataProcessor` branch that Retail actually takes was never exercised, which is how the dead registration shipped.
- The harness now models the **Frame / Region split**: `Texture` and `FontString` widgets do not carry the frame-level methods, because on Retail and WoW Forever a `Texture` is a `Region` and `SetFrameLevel` / `GetFrameLevel` / `SetFrameStrata` / `GetFrameStrata` do not exist on it. Only that verified split is removed — a wider speculative removal would be unverified and would only manufacture false failures. The mock previously handed every widget every method, which is precisely why the `SetFrameLevel` call shipped. With the mock corrected, reverting the guard fails Retail and WoW Forever and still passes TBC Anniversary, matching the reported asymmetry exactly; the same property is asserted for the `HookScript` and `CreateFrame` guards.
- New in-game tests: `Client:TooltipDeliveryPath`, `Client:WidgetTypesAreNotFrameTypes`, `Client:TextureIsARegion` and `Client:CharacterFrameHostExists`. The last two pin the Region/Frame split and the Classic-only frame set per client, so those assumptions cannot be reintroduced silently.
- `Stats:PawnCrossEngineScales` asserted nothing. It passed scale-*looking* strings (`"Classic:WarriorArms"`, `"MrRobot:WarriorArms"`) as `GetScore`'s **guid** argument; `getPlayerGUID` rejected them, so `GetScore` returned at its early-out and the entire scale-name path — the code that shipped the defect — was never run. It asserted only that a nil-guarded early return does not throw, and its name claimed coverage of a "MrRobot" scale that was never actually exercised. Replaced by `Stats:PawnScaleNameContract`, which drives a real player GUID, wraps `PawnGetScaleColor` and `PawnIsScaleVisible` to observe them, and asserts `GetScore` does not raise, visibility is never probed, **every name handed to `PawnGetScaleColor` already exists in `PawnCommon.Scales`**, and that at least one call was actually made so the rest cannot pass vacuously. The existence check — not a hardcoded library name — is the invariant, because the correct name differs by client. Pawn's real behaviour cannot be mocked, so this one has to be asserted in game.
- The tooltip harness models the two talent surfaces **separately**: the Classic family gets `GetNumTalentTabs` and reads the icon from the library's **static** talent table (`CI:GetTalentInfoByClass`), with no `GetInspectSpecialization`; the modern clients get `GetSpecialization` / `GetInspectSpecialization` / `GetClassIDFromSpecID` / `GetNumSpecializationsForClassID`, a `Texture` overlay instead of a `|T` escape, and **no** `GetNumTalentTabs` at all. A single shared mock had been giving the modern clients talent tabs, so the modern talent path was never exercised and its zero output went unnoticed.
- The harness now models **real per-talent ranks** for a two-spec character (group 1 → tab 1 with 21 points, group 2 → tab 2 with 31 points) and asserts the rendered result per group on every client: `[21/0/0]` active and `[0/31/0]` inactive, each carrying an inline `|T` icon. Icon values in the model are deliberately 6-digit fileIDs while ranks are small integers, so the assertion "talent points are small integers, not fileIDs" is what catches a regression of the bug this release fixes.
- It also asserts the active group resolves to 1, that group 1 maps to tab 1 and group 2 to tab 2, and that the Classic family creates no `Texture` overlay, so its rendering path is provably unchanged.
- Two harness defects were found and fixed while doing this, both of which had been masking real gaps: it gave the modern clients talent tabs, so the modern talent path was never exercised; and it wrongly nil'd `GetTalentInfo` / `GetNumTalents` for Titanforge, which zeroed its talent points. Both APIs **do** exist on Titanforge — `GetTalentInfo` plus `TalentInfoQuery`/`TalentInfoResult` are in the generated `C_SpecializationInfo` docs for `classic_titan`, and `GetNumTalents` has 3 real call sites on every Classic branch.
- **`pawn.lua` was never actually executed by four of the five harnesses.** Its
  file-scope `isPawnLoaded` gate returns early unless a Pawn version global or the
  Pawn API exists, and only `settings_test.lua` mocked any of them — so
  `load_test.lua`, `options_test.lua` and `tooltip_test.lua` each loaded the file
  and immediately fell out of it. `load_test.lua` now mocks Pawn on every family.
- **`load_test.lua` now models Pawn's two gated providers per client** and records
  anything written to the chat frame, so the assertion is literally *"the chat frame
  stayed clean"*. Both wrong answers were reintroduced to prove the test bites, and
  each fails on exactly the clients it should: the original `"MrRobot"`-first probe
  fails on the **Classic** family, and a hardcoded `"Classic"` prefix — the fix that
  was shipped first and did not work — passes Classic and fails on **Retail and WoW
  Forever**. A companion check asserts the names actually reached
  `PawnGetScaleColor`, so the chat assertion cannot pass vacuously by never running.
- **The Pawn mock reproduces the *channel*, not an exception.** The real failure
  mode is a chat write, so the mock writes to chat rather than raising; an
  exception-throwing mock would let a bug pass by being swallowed by `pcall`.
- `load_test.lua`'s `C_Timer.After` change was reverted: with the Pawn probe
  removed no test needs to flush a deferred callback, and an unused queue would be
  dead code.
- **The Pawn mock reproduces the API's rejection, not just its returns.** The real
  scale APIs raise for an unknown name; a mock that returned `false` is precisely
  what let a shipped chat-spam defect pass a green suite. `C_Timer.After` in
  `load_test.lua` also had to start recording callbacks instead of discarding
  them, or `_TacoTipPawnReady` would stay `false`, the colour call would be
  skipped, and the scale-name assertion would pass vacuously. This is the fourth
  instance this release of a mock that modelled a return value where the real API
  rejects — after all-methods widgets hid the `Region`/`Frame` split, a no-op
  `hooksecurefunc` hid the unguarded `HookScript`, and mock-inventing
  `CharacterModelFrame` hid the missing frame on Retail.
- `locale_test.lua` covers the Titanforge pin: Titanforge resolves to `zhCN` whatever `GetLocale()` reports, an explicit override still wins on Titanforge, and the other four families continue to follow the client language. `load_test.lua`'s active-locale assertion is family-aware for the same reason.
- `Tests/harness/README.md` documents the mocking invariants that the assertions depend on, so a future mock change cannot silently make a whole file pass for the wrong reason.

#### Settings frame

`options_test.lua` only proved the pages *build*. It never asked whether the
controls were *bound*, so a control wired to the wrong key, a typo'd setting name,
or a setting with no control at all would pass. `settings_test.lua` closes that
gap without hand-maintaining a control-to-key mapping: it drives every control the
build created, diffs `TacoTipConfig` before and after, and asserts that the set of
settings the controls can reach is exactly the set `GetDefaults()` declares. It
runs 20 ways (5 clients × 2 registration paths × 2 Pawn states) and asserts:

- all **66** settings are reachable from a real control, and no control writes a
  key that is not a declared setting;
- every setting is read by at least one runtime file, so nothing is dead weight;
- values survive a save/load round-trip, a missing saved key is backfilled from
  the default, and an out-of-range saved value is clamped rather than accepted;
- **Reset configuration** restores every default (it is located by *behaviour*,
  because labels are localised and Titanforge runs in Chinese — an English string
  match finds nothing there);
- each client uses the right registration API: `Settings.RegisterCanvasLayoutCategory`
  + `RegisterAddOnCategory` + 3 subcategories + `OpenToCategory` on Retail and
  Forever, `InterfaceOptions_AddCategory` (root + 3 children) +
  `InterfaceOptionsFrame_OpenToCategory` on the Classic family, with the two paths
  also cross-checked in the opposite configuration;
- the achievement-points toggle is enabled on Titanforge / Retail / Forever and
  disabled on Classic Era / TBC, and the Pawn toggle is gated on Pawn being
  installed — both asserted from the **default** state, so the gating is verified
  where the user actually meets it;
- no control handler raises an error, and no control reaches the runtime error
  handler.

The options UI turns out to **cascade**: a control is disabled while the setting it
depends on is off, so a single sweep only reaches what is reachable from the
default state. The harness therefore walks the dependency tree in rounds, re-opening
the cascade before each control, with no parent/child table hardcoded. The settings
found gated in the default state are exactly the expected ones — the eight overlay
offsets, `show_gs_items_hs`, `show_guild_rank`, `tooltip_portrait_3d`, the portrait
scale and zoom, and `unlock_info_position`.

Writing it surfaced four defects in the harness itself, each of which had been
masking real coverage: the sweep only looked at *named* widgets, so the nameless
"Reset configuration" button was never clicked (`createOptionsButton` is the one
builder that does not default a global name, matching the Classic reference); the
enable-state test used the `a and b or true` trap, which is always true when the
middle term is false and so marked every disabled widget enabled; `onValueChanged`
was invoked as a method though it is declared `function(value)`, writing the
control itself into the config; and the mock `ColorPickerFrame` took positional
arguments where the real API takes one info table and calls back through
`swatchFunc`, so the colour swatches appeared to bind to nothing. Two further mock
gaps were needed for the buttons to work at all: named frames must become globals
(as they do in WoW) and `xpcall` must exist and route to its handler.

No addon source change was required.

### API audit

A usage-based sweep (not a doc-table lookup) of every UI, unit, item, timer and
namespace API the addon calls, counted against real call sites in each
Blizzard branch, found three genuine cross-client gaps and confirmed the rest:

- `GetNumTalentTabs` **does not exist on WoW Forever or Retail** (3 call-site
  files on each Classic branch, 0 on Forever/Retail). `cacheUnitData` and
  `GetSpecializationIndex` / `GetTalentPoints` all test it before calling, and
  the `elseif` is preceded by the `C_SpecializationInfo.GetInspectSpecialization`
  arm — which exists only on Forever/Retail (0 on the Classic branches). The
  two families therefore dispatch to complementary branches, and neither path
  can reach a missing function.
- `C_SpecializationInfo.GetInspectSpecialization` is modern-only; already
  `pcall`-guarded, because Retail marks it secret-restricted.
- `InterfaceOptions_AddCategory`, `InterfaceOptionsFrame_OpenToCategory` and
  `InterfaceOptionsFrame_Show` have **no** occurrences anywhere in the
  FrameXML source on any branch — they are engine-exposed, not shipped as
  FrameXML, so their presence cannot be confirmed from source either way. The
  legacy options path is therefore covered by the offline harness (which
  exercises it with the namespace absent) rather than by a source check.

---

## [0.7.7] — 2026-09-21

### Universal Cross-Engine Architecture

- **Multi-Engine Client Family Detection (`LibForeverInspector`):**
  - Added runtime engine detection routines: `IsRetail()`, `IsForever()`, `IsWotlk()`, `IsTBC()`, and `IsClassic()`.
  - Registered backward-compatible `LibClassicInspector` alias inside `LibStub` to preserve complete transparency for legacy modules.
  - Client Build Major detection distinguishes Classic Era (1), TBC (2), WotLK (3), WoW Forever (`interfaceVersion >= 16000`), and Retail (`clientBuildMajor >= 10` or `WOW_PROJECT_MAINLINE`).

- **Dynamic Tooltip Hooking Pipeline:**
  - Modern engines (Retail / Forever): Uses `TooltipDataProcessor.AddTooltipPostCall` for unit (`Enum.TooltipDataType.Unit`) and item (`Enum.TooltipDataType.Item`) processing.
  - Classic engines (Classic Era / TBC / WotLK): Uses secure script hooks `GameTooltip:HookScript("OnTooltipSetUnit")` and `OnTooltipSetItem`.
  - Unified unit resolution (`resolveTooltipUnit`) seamlessly handles `TooltipUtil.GetDisplayedUnit(tooltip)`, `tooltip:GetUnit()`, and GUID fallback matching.

- **Adaptive GearScore & Item Level Engine:**
  - Dynamic bracket sizing: 200 for Classic Era, 400 for TBC Anniversary, and 1000 for WotLK, WoW Forever, and Retail.
  - Safe `C_Item.GetItemInfo` / `GetItemInfo` dual-bridge resolution.
  - Uncached equippable item handling with `C_Item.ContinueWithCancelOnItemLoad` and `C_Item.RequestLoadItemDataByID`.

- **Pawn Universal Compatibility:**
  - Dynamic Pawn scale detection supporting modern `"MrRobot:"` scales and legacy `"Classic:"` scales.
  - Dual version gating accepting `PawnLastUpdatedVersion` (Retail/Forever), `PawnClassicLastUpdatedVersion` (Classic), and direct public function signatures.
  - Safe-guarded all score lookups against missing globals or unexpected return values.

- **Cross-Engine Talent Points Resolution:**
  - Audited Blizzard FrameXML UI source (`wow-ui-source`) across all client branches.
  - Implemented `getTalentTabPoints` in `LibForeverInspector` to automatically handle 3-return (1.12 legacy), 5-return (Classic Era / TBC Anniversary / WotLK), and 7-return (`C_SpecializationInfo.GetSpecializationInfo`) layouts without data truncation.
  - Implemented gender-correct specialization names via `UnitSex` and `GetSpecializationInfoByID`.

- **Universal Settings & ColorPicker UI:**
  - Dual settings registration supporting modern `Settings.RegisterCanvasLayoutCategory` / `Settings.RegisterCanvasLayoutSubcategory` and legacy `InterfaceOptions_AddCategory`.
  - Universal color picker bridging modern `ColorPickerFrame:SetupColorPickerAndShow(info)` and legacy `ColorPickerFrame:SetColorRGB(...)` / callback properties.

- **Zero-Allocation Tooltip Pipeline:**
  - Static record pooling via `addLineDouble(...)` and `addLineSingle(...)` with `wipe(pooledTooltipText)` and `wipe(pooledLinesToAdd)` eliminating memory pressure and GC spikes on high-frequency mouseovers.
  - Synchronous visual isolation (`clearTooltipVisuals`) resetting borders, portraits, models, and power bars on every non-unit transition.
  - Integer-floored color codes (`makeColorCode`) preventing float precision formatting issues in modern Lua.

- **Automated In-Game Testing (`/tttest`):**
  - Full 10-suite WoWUnit automated test suite verifying Core, Config, Borders, Portrait, Guild, Stats, Mover, Modules, MinimapAndAnchor, and Lifecycle invariants (162 tests passing).
