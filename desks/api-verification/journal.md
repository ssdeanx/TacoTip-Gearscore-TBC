# api-verification — Journal

## 2026-10-14 — NOTE from the tacotip desk: the "SERVER response" claim in the entry below is not supported by the mirror

Read the 2026-10-14 entry's item 2 before reusing it. It states: *"It is a SERVER
response. `LE_GAME_ERR_*` is a C-side enum an addon cannot fabricate. So the popup
is proof that something sent a request and the server refused it."* A mirror-only
audit (run 2026-10-14, after the entry) does not support that inference:

1. **"A C-side enum cannot be fabricated" does not imply "the server sent it."**
   The client's own C code raises `LE_GAME_ERR_*` values too — that is exactly what
   the client-side UI error path is. The inference needs an extra premise that is
   not in the mirror.
2. **No producer for an inspect refusal appears in the mirror.** Nothing in any
   Lua on any branch says a refused `CanInspect` or a refused `NotifyInspect`
   raises `UI_ERROR_MESSAGE`. What the mirror shows is the **sink**:
   `Blizzard_UIErrorsFrame/Classic/UIErrorsFrame.lua:140-146` displays and speaks
   it, and `:90` shows the per-client throttle entry — which the entry already had
   right.
3. **The delivery path points at event dispatch, not at a call made from inside a
   C API.** `UIErrorsFrame` consumes `UI_ERROR_MESSAGE` via
   `UIErrorsMixin:OnEvent` → `TryDisplayMessage` → `AddMessage`, and Blizzard's own
   suppression of these messages is event-level — it unregisters the event
   (`Blizzard_ChatFrameBase/Shared/SlashCommands.lua:1305-1310`) — which is only
   coherent if the event is what reaches the frame. Whether *this* message is
   synchronous or event-delivered is still NOT IN MIRROR; the current guard covers
   both rather than assuming either.
4. **`_G.ERR_OUT_OF_RANGE` / `ERR_INVALID_INSPECT_TARGET` / `ERR_UNIT_NOT_FOUND`
   appear nowhere in the mirror, and no GlobalStrings file exists on any branch.**
   Any code that matches on those globals, or that requires `_G[name] == message`,
   is relying on something this desk cannot verify. The guard matches the
   `errorName` that `GetGameMessageInfo` returns instead — and the entry's item 4
   ("this weakens the `showError` theory") is consistent with that.

This desk owns truth claims; the claim above should be downgraded to UNKNOWN
pending a live-client observation. Recorded here rather than edited in place so the
wrong turn stays readable. — tacotip desk, 2026-10-14

## 2026-10-14 — Desk opened

- **Purpose:** be the desk that answers *"does this Blizzard API exist, and does it
  behave this way on client X?"* — with evidence, before anyone writes it into
  add-on code, a test, or a comment. TacoTip ships to five client families, and
  the differences between them are exactly where this add-on has historically
  broken.
- **Scope:** the Blizzard FrameXML mirror at `/home/sam/wow-ui-source`, the API
  contract this add-on relies on (Inspector, tooltip, unit, item, addon-message,
  settings APIs), and the *evidence rules* the other desks use. This desk does not
  own product code; it owns the truth claims about it.
- **Deliverable:** [`bench/audits/2026-10-14-wow-ui-source-api-verification.md`](../../bench/audits/2026-10-14-wow-ui-source-api-verification.md)
  — the full playbook with worked examples. This journal is the running record.

### The rule this desk exists to enforce

A Blizzard claim is VERIFIED only when it names a **branch + path + line** in
`/home/sam/wow-ui-source`. Blizzard's *generated API documentation* and Blizzard's
*own call sites* are different kinds of evidence and they disagree — the call site
wins, because the engine is what runs.

### Findings recorded so far (all VERIFIED, 2026-10-14)

1. **`CanInspect` — published signature vs. real call.** The generated doc
   (`origin/classic_era:Interface/AddOns/Blizzard_APIDocumentationGenerated/PlayerScriptDocumentation.lua`)
   lists one argument (`targetGUID`). Blizzard's own inspect flow calls
   `CanInspect(unit, true)` (`Blizzard_InspectUI/Vanilla/Blizzard_InspectUI.lua`
   and `.../TBC/...`, `InspectFrame_Show`). So the second argument is real even
   though it is undocumented — and the *documented* classic signature cannot be
   relied on to carry range. This is why `LibForeverInspector.requestInspect`
   re-checks `CheckInteractDistance(unit, 1)` for the classic family rather than
   trusting the flag alone.
2. **`CheckInteractDistance(unit, distIndex)` — what the indices mean.** Blizzard's
   unit popups gate their buttons with it
   (`Blizzard_UnitPopupShared/UnitPopupSharedButtonMixins.lua`: trade `2`, duel
   `3`, follow `4`, base `nil`; used by `UnitPopupSharedUtil.IsEnabled` in
   `UnitPopupSharedUtils.lua`). Index `1` is the inspect-range class — which is
   what `INSPECT_INTERACT_DISTANCE_INDEX = 1` has always assumed.
3. **`UnitDistanceSquared` — the second return matters.** The doc returns
   `(distance, checkedDistance)`. Blizzard's own consumer only trusts the value
   when `checkedDistance` is true
   (`Blizzard_UnitFrame/Shared/CompactUnitFrame.lua`, `CompactUnitFrame_UpdateDistance`),
   and compares it as a **squared** quantity. TacoTip's `inspectDistanceSquared`
   does the same, and treats a non-`true` flag as *unmeasurable* — which is why the
   pre-filter falls through to `CheckInteractDistance` instead of refusing.
4. **Absence is not evidence.** The `Not in Range` / `Can't inspect` error text
   appears **nowhere** in the checkout — it is an engine string, not FrameXML. A
   session that greps the mirror, finds nothing, and concludes the error does not
   exist will "fix" the wrong thing. Range refusal is only observable in-game.

## 2026-10-14 — `CanInspect`'s second argument is `showError`, not a range gate

A standing claim in `AGENTS.md`, in `CHANGELOG.md` 0.8.3 item 3, and in a
`LibForeverInspector` comment was **wrong and shipped**. Correcting the record
here because the next session will read the code comment before it reads this.

1. **The wrong claim.** "All five branches of `Blizzard_InspectUI` gate this exact
   call with `if (CanInspect(unit, true)) then NotifyInspect(unit) end` … the
   second argument is the range flag." Blizzard *does* pass two arguments, on
   every branch. But argument two is **`showError`** — *"if true, display an error
   message ('You can't inspect that unit'); this function doesn't check whether
   you're close enough to the unit to inspect it; use `CheckInteractDistance` for
   that."* So `CanInspect` never tested distance, and passing `true` asks the
   **engine to display a message**. A call added to suppress an out-of-range
   popup was itself a source of one.
2. **Where the meaning is, and is not.** The `showError` semantics are in two
   *external* API references (warcraft.wiki.gg, WowWiki archive), in identical
   wording. They are **not** in the mirror. The mirror's generated docs list
   `CanInspect` with a **single** argument on `classic_era`, `classic_anniversary`,
   `classic_titan`, `forever` and `live` alike — an arity gap in the
   `FunctionParameters` block, not evidence the flag is absent. **Do not cite the
   mirror as the source of this meaning; it cannot be.**
3. **The mirror's actual contribution is structural, and weaker.**
   `Blizzard_UnitPopupShared/UnitPopupSharedButtonMixins.lua` calls the **one**-arg
   form `CanInspect(contextData.unit)` to decide whether to enable a popup button;
   `Blizzard_InspectUI` calls the **two**-arg form from `InspectFrame_Show`. A
   range flag would have one form and be passed everywhere. Two forms differing
   exactly on the "tell the player" axis is `showError` — and `InspectFrame_Show` is
   reached only from explicit user action (`/inspect`, right-click → Inspect),
   where a message is the intended outcome. This makes `showError` the better
   reading; it does not establish it.
4. **The method error, which is the part worth keeping.** The old comment read the
   docs' one-argument listing and concluded *"the docs say one argument, therefore
   the range flag cannot be the whole gate."* Then `git grep` showed Blizzard
   **passing** the two-argument form, and that was treated as confirming it. **A
   call site proves a name is used; it says nothing about what an argument
   *means*.** This is the `AGENTS.md` warning ("do not infer an API surface from a
   loose grep") biting through the exact inference it names — and it survived
   precisely because the grep *did* find a hit.
5. **`pcall` never suppressed this class of popup.** `UI_ERROR_MESSAGE` travels
   into `UIErrorsFrame`, a different frame from the call stack, so wrapping
   `NotifyInspect` cannot stop it. Blizzard's own suppression is an **event
   registration** (`SlashCommands.lua` unregisters/re-registers
   `UI_ERROR_MESSAGE`). Any changelog claim that `pcall` or a per-unit cooldown
   "stops the error" is describing request *volume*, not the popup.

**Open, not closed:** attribution. Removing the `showError` call is safe (fewer
arguments can never loosen a gate) but is **not established** as the cause of the
player's popup. `notifies` / `rejected` / `lastError` are cumulative since
`/reload`, so they read zero whether no inspect was attempted or one was and
something else raised the message — opposite fixes. A bounded capture
(`lib.errorLog`, `kind = "notify"` vs `kind = "error"`) was added to separate them.
Decide from that log before writing another fix on this path.

## 2026-10-14 — "Out of Range" is a real engine error, throttled on Retail, deliberately NOT throttled on the Classic clients

Follow-up to the `CanInspect` entry above. This is the piece that explains why
the report is Classic-only, and it came out of the mirror, not the web.

1. **`LE_GAME_ERR_OUT_OF_RANGE` is a genuine engine error constant**, delivered on
   `UI_ERROR_MESSAGE` and resolved through `GetGameMessageInfo` for the sound.
   The popup you see — red text **and** sound — is that path.

2. **It is a SERVER response.** `LE_GAME_ERR_*` is a C-side enum an addon cannot
   fabricate. So the popup is proof that something sent a request and the server
   refused it. It is *not* proof of which caller sent it — an addon Lua error
   cannot produce this.

3. **The per-client asymmetry that explains "only Classic Era":**

   | branch | `UIErrorsFrame.lua` | throttled? |
   | :--- | :--- | :--- |
   | `classic_era` | line 90 | **no** — `--[LE_GAME_ERR_OUT_OF_RANGE] = true,` |
   | `classic_anniversary` | line 90 | **no** — same, commented |
   | `classic_titan` | line 90 | **no** — same, commented |
   | `live` (Retail) | line 92 | **yes** — live entry |

   On the three Classic clients Blizzard has the throttle entry **commented out**,
   so every occurrence produces a full popup with no de-duplication. On Retail it
   is active, so a repeat collapses. Same server behaviour, different noise. This
   is why the bug is Classic-only and why Retail looks clean — and it means
   "fixed on Retail" is not evidence the code path differs.

4. **This *weakens*, not strengthens, the `showError` theory as the cause.**
   `CanInspect`'s `showError` is a **client-side** "You can't inspect that unit",
   which is a different message from a server `LE_GAME_ERR_OUT_OF_RANGE`. The
   `CanInspect` fix stands on its own (it was demonstrably asking the engine to
   display a message), but it should not be credited with the reported popup
   without evidence.

5. **No inspect-specific `LE_GAME_ERR_*` exists in FrameXML** — the enumerated
   names are all spell/resource/ability errors. Do **not** read that as proof
   none exists: only constants *referenced by FrameXML* appear in a grep, and
   this enum is C-side. Absence in the mirror is not evidence of absence.

**Method:** `GetGameMessageInfo` is the resolver, so a capture on
`UI_ERROR_MESSAGE` that records `messageType` **and** the resolved string
separates "client-side showError text" from "server out-of-range response"
without needing to guess which one you are looking at. That is the whole point
of `lib.errorLog`'s `kind = "error"` entry.

### Standing queue

- When someone asks "is this API safe on client X", answer here first, then let the
  asking desk write the code.
- Keep the client → branch map current (it is in the playbook).
- Re-check the three findings above at the next client patch: `version.txt` and
  `git log -1 origin/<branch>` are the freshness signal for each branch.

### Evidence

    cd /home/sam/wow-ui-source
    git --no-pager log --oneline -1 origin/classic_era        # 1.15.9 (70003)
    git --no-pager log --oneline -1 origin/classic_anniversary # 2.5.6 (70006)
    git grep -n "CanInspect(" origin/classic_era -- '*.lua'
