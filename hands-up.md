# hands-up

escalation procedure — when each signal fires, and what reaches the operator.

signals are JSON files: `desks/<name>/.signals/<timestamp>.json`. include an
ISO 8601 UTC `timestamp`; the dashboard orders by it. `run_id` pairs a signal
with a later outcome signal.

## signal types

| signal | fires when | `signal_type` / `subtype` |
| :--- | :--- | :--- |
| hands-up | two desks disagree and can't settle it against external facts | `escalation` / `hands-up` |
| blocked | a desk can't proceed without input — missing access, ambiguous scope, a decision only the operator can make | `escalation` / `blocked` |
| done | work is complete and ready for review; artifacts are on the bench | `execution` / `done` |
| checkpoint | significant progress worth noting; work continues | `execution` / `checkpoint` |
| partnership | the TA reports coordination quality | `partnership` / `partnership` |

escalations sort to the top. don't signal routine progress; `blocked` means
truly blocked — if a reasonable default exists, proceed and note it.

## problems seen in practice

the 0.8.4 release cost five hours to a set of problems that all had the same
shape. they are here because the procedure should catch them, not because
they are interesting.

- **two lanes editing the same file.** a lane was given a task that reached
  into another lane's files, and neither knew. the symptom was two edits
  fighting over `options.lua` and `main.lua`. **the fix is the desk signal:**
  the owning lane writes `done`, the next lane waits for it and re-reads the
  file immediately before editing. if you do not know who owns a file, you do
  not own it yet.
- **a brief with a wrong assumption, corrected by message.** the brief told a
  lane to cap a slider at a value the operator had never asked for; two
  follow-up messages were needed to withdraw it, and by then the lane had
  already built the brief's mistake into its work. **a wrong brief is replaced
  by a fresh, complete brief** — corrections to a running lane compound.
- **an audit reporting an absence it could not verify.** a reviewer without
  access to the mirror asserted that a client API did not exist, and the
  operator had already proven in game that it worked. an absence claim needs
  a whole-tree sweep AND the generated api docs; without them it is ASSUMED
  (see `CAIRN.md`), and it is never a defect report.
- **a mock agreeing with the code instead of the client.** three real,
  user-visible defects shipped behind a green suite because the mock handed
  the addon API the client does not give it. **the mock must reproduce what
  the client LACKS**, not only what it returns — and the fix is a pin that
  goes red on the old code.
- **changing a mechanism without knowing what it does.** 0.8.4 changed three
  things the operator had to find in game: the tooltip name size, the tooltip
  anchor gate, and what the scan does to the tooltip. each was a change to a
  mechanism nobody had read end to end, and each shipped behind a green
  suite. **the fix:** read the whole path first, and pin the client shape it
  broke — the classic-family unit tooltip is not the modern one
  (`workshop.md` → "what the client actually does").
- **tests that cannot fail.** the harness pinned values by copying them out
  of the code, so a wrong value in the code passed a green suite — the
  tooltip name size shipped that way. **the fix:** assert a literal or an
  independent derivation, and show every new pin going red on a copy before
  it is accepted. a green suite means nothing if the pin cannot fail.
- **verification that never ran.** a lane changed behaviour, was stopped, and
  left the tree red; nobody knew until the next lane ran the suite. **a lane
  that changes behaviour reports only after the suites, the lint and both
  package verifiers are green.** "done" with a red tree is not a finish.
- **a green suite announced as a fix.** four consecutive rounds of "fixed" on
  one tooltip defect, each behind a passing pin, each still wrong on the
  operator's screen. the pin proved the code did what the lane described; it
  did not prove the player-visible result changed. **the fix:** a lane reports
  "pinned in the harness, not observed in game" — never "fixed". the operator's
  next hover is the only acceptance, and a lane that has no such observation
  says exactly that in its `done` signal.
- **a decision built on a predicted rect.** the portrait's side was computed
  from the handle position plus `tooltip:GetWidth()` while the tooltip had not
  been laid out, so the decision read a prediction of the frame's geometry. every
  later round — cache key, show-time pass, deferred guard — was downstream of
  that one prediction. **the fix:** a geometry decision reads the laid-out frame,
  from a deferred pass when the render is too early. a computed rect is an
  assumption wearing a number.
- **four inferred fixes before one measurement.** each round had a plausible
  story and no evidence from the client, and the operator paid for it in
  testing time. **the fix:** when a symptom survives one fix, the next step is
  an instrumented readout the operator can produce with one hover — the real
  rect, the width, the side, the counters — not another reading of the same
  code.
- **a pin that passed while the fix was reverted.** a follow-up-arming pin went
  green against reverted code because an earlier block had left the portrait
  mock parked off screen, so the "idle" pass was not idle. **the fix:** every
  pin resets the mock state it depends on, and the revert proof runs per pin —
  a pin proven only inside its own block has proven nothing.
- **"checked all clients" without the operator's branch.** the branch the
  operator actually plays was checked after the claim instead of before, and it
  turned out to declare no `OnShow` on the `GameTooltip` frame — so one layer of
  the fix never installed on their client. **the fix:** the operator's branch is
  the first one checked and the one that can withdraw a claim.
- **the 0.8.4 state-machine overcomplication and revert.** an attempt to
  replace the inspect system with a complex asynchronous three-state machine
  (`inspectStates.QUEUED == "queued"`) broke multiple client paths and caused
  widespread regressions. the codebase had to be reverted to the known-good
  0.8.3 base and incrementally fixed forward to 0.8.6. offline test harnesses
  that had been modified to assert the abandoned tri-state semantics were left
  failing. **the fix:** do not replace working state machines with complex
  architectural rewrites when simple guards suffice; keep test harness
  assertions synchronized with production client contracts.
- **Classic Era GameMenu Exit/Logout button taint (`ADDON_ACTION_FORBIDDEN`).**
  detouring `_G.PlaySound` in `installInspectErrorSuppressor` tainted execution
  when `GameMenuFrame` invoked `PlaySound(...)` immediately prior to protected
  `Quit()` or `Logout()`, triggering `[ADDON_ACTION_FORBIDDEN] AddOn 'TacoTip'
  tried to call the protected function 'UNKNOWN()'`. **the fix:** never replace
  `_G.PlaySound`. mute the out-of-range inspect sound at `GetGameMessageInfo`
  inside `UIErrorsMixin:TryDisplayMessage` by returning `soundKitID = nil` for
  `ERR_OUT_OF_RANGE`.
- **first-hover partial GearScore (GS 104) async texture-vs-link race.**
  `INSPECT_READY` fired before item links were cached locally in the client.
  `GetInventoryItemLink` returned `nil`, but `GetInventoryItemTexture` was
  valid. the old code treated nil as empty, stamped `data.time = now`, and
  locked in a partial score for 5 minutes. **the fix:** check
  `GetInventoryItemTexture`. if a texture exists but link is nil, mark
  `incomplete = true`, do not stamp cache time, and retry after 250ms with
  `PlayerGUIDToUnitToken(guid)`.
- **bag item hover tooltip stretch / disappearance.** Blizzard's
  `ContainerFrameItemButton_CalculateItemTooltipAnchors` does not call
  `ClearAllPoints()`. hooking `GameTooltip_SetDefaultAnchor` without gating
  container buttons caused `GameTooltip` to be pinned to both
  `TacoTipDragButton` and the bag slot button simultaneously, stretching the
  tooltip across the screen. **the fix:** strictly exclude container item
  buttons from default anchor manipulation so Blizzard's single slot anchor
  remains intact.
- **3D world mouseover focus returning empty table.** `GetMouseFoci()` returns
  an empty table `{}` in 3D world space on modern engines. checking `frames[1]`
  without a fallback caused `TT:GetMouseFocus()` to return `nil`. **the fix:**
  if `frames` is empty, return `WorldFrame`.
- **packaging failures on unignored tooling dotfiles.** tracked configuration
  files like `.wowluarc.json` without `export-ignore` in `.gitattributes` cause
  release package verifiers to fail. **the fix:** keep `.gitattributes`
  synchronized with all tracked non-runtime files.

**when to signal `blocked`:** when the only way forward is a decision the
operator must make (a version to hold, a value to change, a feature to drop).
**when to signal `hands-up`:** when two desks disagree and the client source
cannot settle it. **when neither applies:** proceed with the defensible
default, note it in the journal, and keep going — that is what `guarded()`
and the `checkpoint` signal are for.

## journal note

each signal also gets a marker in the desk's journal:

```markdown
## <date> — [signal:<type>] <summary>
- <key details>
```

## outcome signals

a reviewer can rate a delivered result — same `run_id`, `signal_type:
"outcome"`, `quality_rating` (0–5), `effort_to_merge` (`minimal` / `moderate` /
`significant`), optional `issues_found`. the dashboard compares `quality_rating`
to the desk's self-assessed `confidence` — the honesty gap.
