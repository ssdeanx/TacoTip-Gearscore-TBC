# hands-up

escalation procedure — when each signal fires, and what reaches the operator.

signals are JSON files: `desks/<name>/.signals/<timestamp>.json`. include an
ISO 8601 UTC `timestamp`; the dashboard orders by it. `run_id` pairs a signal
with a later outcome signal.

## operator invariants (do not relitigate)

- **the FojjiCore row block stays, and it is specific to FojjiCore.** the row
  is switched off through FojjiCore's own published option
  (`FojjiCoreNS.Tooltips.Set("bisGearScore", false)`) at load and on
  `ADDON_LOADED` for `FojjiCore`/`FojjiCore_BiS`. never replace
  `GameTooltip.AddLine`/`AddDoubleLine` to do it: that taints Blizzard's
  secure aura pipeline. it is not a generic filter for every addon. the
  UnitFrame mover text and the UnitAura secret taint are separate problems;
  the block is not a lever for either.

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

these failures cost dozens of hours across the 0.8.3–0.8.7 releases. each item
represents a real, user-visible bug or broken workflow. they are grouped by
operational domain so lanes do not re-learn them the hard way.

### 1. Lane discipline & developer process

- **two lanes editing the same file.** a lane reached into another lane's files
  without coordination, causing merge fights over `options.lua` and `main.lua`.
  **the fix:** desk signals. the owning lane writes `done`, the next lane waits
  for it and re-reads the file immediately before editing. if you do not know
  who owns a file, you do not own it yet.
- **a brief with a wrong assumption, corrected by message.** a brief instructed
  a lane to cap a slider at an unwanted value; subsequent corrections arrived
  after the mistake was already baked into code. **the fix:** a wrong brief is
  replaced by a fresh, complete brief — never patch a confused running lane.
- **editing working production code when tasked with tests.** an agent tasked
  with fixing failing test suites mutated working runtime files
  (`LibForeverInspector.lua`, `TacoTip_Extras.toc`, `main.lua`) to satisfy
  outdated harness assertions, breaking working state and violating task
  boundaries. **the fix:** NEVER touch working production or library code when
  assigned to tests. If a test fails against working code, update or comment out
  the obsolete test assertions; never mutate working code.
- **tests that cannot fail.** the harness pinned values by copying them out of
  the code, so a wrong value in the code passed a green suite. **the fix:**
  assert a literal or an independent derivation, and show every new pin going
  red on a copy before it is accepted.
- **a mock agreeing with the code instead of the client.** three real defects
  shipped behind a green suite because the mock handed the addon an API the
  client does not provide. **the fix:** the mock must reproduce what the client
  LACKS, not only what it returns — and the fix is a pin that goes red on old code.
- **a green suite announced as a fix.** four consecutive rounds of "fixed" on
  one tooltip defect, each behind a passing pin, each still wrong on the
  operator's screen. **the fix:** report "pinned in the harness, not observed
  in game" — never "fixed". The operator's next in-game observation is the only
  true acceptance.
- **verification that never ran.** a lane changed behaviour, stopped, and left
  the tree red; nobody knew until the next lane ran the suite. **the fix:** a
  lane reports only after test suites (`run_all.sh`), static analysis (`luacheck .`),
  and release package verifiers (`verify_release.sh --worktree`) are 100% green.
- **attempting to re-enable scan when scan crashes both addons.** an agent
  assumed disabled scan code was a bug and attempted to re-enable it. Scan in
  TacoTip_Extras was intentionally disabled because it crashes both addons.
  **the fix:** never assume or guess why code is disabled; read `workshop.md`
  and operator invariants. Scan remains strictly disabled.
- **pins that assert behavior the operator explicitly banned.** the 0.9.2
  Forever talents gate turned two `tooltip_test FOREVER` pins red that assert
  the old talents-on-Forever readout. they cannot go green without violating
  the operator's order, and the shared file that holds them cannot be edited
  per the test-lane boundary. **the fix:** retire or re-scope operator-overruled
  pins by operator decision; report the red pins plainly instead of gaming them.

### 2. Geometry, tooltip layout & FrameXML traps

- **decisions built on a predicted / pre-layout rect.** the portrait's side was
  computed from the handle position plus `tooltip:GetWidth()` before the tooltip
  had been laid out, placing the portrait off-screen. **the fix:** never read
  screen geometry (`:GetLeft()`, `:GetTop()`, `:GetRight()`, `:GetWidth()`,
  `:GetHeight()`) inside the render pass before layout. The only sanctioned
  reader is `getPortraitSideRightEdge` which measures the handle's target edge.
- **bag item hover tooltip stretch / disappearance.** Blizzard's
  `ContainerFrameItemButton_CalculateItemTooltipAnchors` does not call
  `ClearAllPoints()`. Hooking `GameTooltip_SetDefaultAnchor` without gating
  container buttons caused `GameTooltip` to receive dual anchors, stretching the
  tooltip across the screen. **the fix:** strictly exclude container item
  buttons from default anchor manipulation so Blizzard's single slot anchor
  remains intact.
- **3D world mouseover focus returning empty table.** `GetMouseFoci()` returns
  an empty table `{}` in 3D world space on modern engines (TBC Anniversary,
  Retail, Forever). Checking `frames[1]` without a fallback caused
  `TT:GetMouseFocus()` to return `nil`. **the fix:** if `frames` is empty,
  fall back to `WorldFrame`.
- **plain frames lacking backdrop API.** `SetBackdrop` / `SetBackdropColor`
  exist only on `BackdropTemplate` or `BackdropTemplateMixin` frames. A frame
  created via `CreateFrame("Frame", ...)` has none, and unguarded calls error or
  silently drop borders.

### 3. Inspection, taint & client engine contracts

- **Classic Era GameMenu Exit/Logout button taint (`ADDON_ACTION_FORBIDDEN`).**
  detouring `_G.PlaySound` in `installInspectErrorSuppressor` tainted execution
  when `GameMenuFrame` invoked `PlaySound(...)` immediately prior to protected
  `Quit()` or `Logout()`, triggering `[ADDON_ACTION_FORBIDDEN] AddOn 'TacoTip'
  tried to call the protected function 'UNKNOWN()'`. **the fix:** never replace
  or detour `_G.PlaySound`. Mute the out-of-range inspect sound at
  `GetGameMessageInfo` inside `UIErrorsMixin:TryDisplayMessage` by returning
  `soundKitID = nil` for `ERR_OUT_OF_RANGE`.
- **first-hover partial GearScore (GS 104) async texture-vs-link race.**
  `INSPECT_READY` fired before item links were cached locally in the client.
  `GetInventoryItemLink` returned `nil`, but `GetInventoryItemTexture` was
  valid. The old code treated nil as empty, stamped `data.time = now`, and
  locked in a partial score for 5 minutes. **the fix:** check
  `GetInventoryItemTexture`. If a texture exists but link is nil, mark
  `incomplete = true`, do not stamp cache time, and retry on the
  `{0.20 .. 1.50}` ladder with `PlayerGUIDToUnitToken(guid)`.
- **the same defect survived in the exhaustion branch (found in 0.8.8).** The
  0.8.7 fix applied "do not stamp cache time" to the retry path, but the
  `retriesExhausted` branch still wrote `data.time = now` and cleared
  `incomplete`. On a FIRST inspect that never resolved, the record was empty
  yet looked fresh for the full 300 s window: no GearScore line and no
  re-inspect for five minutes, which is exactly the reported "sometimes no
  score". **the fix:** leave `.time` alone, keep `incomplete = true`, clear
  `retryPending`, and park the entry for 20 s (`failedUntil`, `GetTime`) so it
  is asked again soon without hammering `NotifyInspect` on every hover. Also:
  failed records are now reclaimable by eviction (aged by `lastAttempt`), so
  they can no longer defeat the 512-entry ceiling.
- **`CanInspect` called with two arguments.** Passing a second argument
  (`showError = true`) makes the client engine display red "Not in range"
  popups and spoken error audio on hovered units. **the fix:** call
  `CanInspect(unit)` with exactly ONE argument.
- **the 0.8.4 state-machine overcomplication and revert.** An attempt to
  replace the inspect system with a complex asynchronous three-state machine
  broke multiple client paths and caused regressions, requiring a revert to
  0.8.3 and incremental forward fixes. **the fix:** do not replace working
  state machines with complex architectural rewrites when simple guards suffice.
- **client misclassification from `GetBuildInfo()` slot layouts.** Classic Era
  returns `nil` in slot 4 and the build in slot 7, causing naive build checks to
  misclassify Era as Mainline. **the fix:** identify client families from
  `WOW_PROJECT_ID` alone (2 for Era, 5 for TBC, 11 for Titanforge).

### 4. Diagnostics, telemetry & packaging blindspots

- **diagnostic false clean reports and swallowed pcall errors (`/tt diag`).**
  `/tt diag` previously relied on `TT.lastTooltipError` which was only set if
  `handlePipelineError` fired, while internal `pcall` invocations (`DoInspect`,
  `portrait.SetUnit`, `portrait.ClearModel`, `TacoTip_GSCallback`) swallowed error
  returns completely, leaving `/tt diag` reporting "no problems detected" even
  while features silently failed. Furthermore, it lacked live unit context.
  **the fix (0.8.7):** install `TT:RecordError` ring buffer (last 15 entries with
  timestamps and subsystem tags) across internal `pcall` sites, add dynamic problem
  detection for inspect stalls (>3s), unresolved unit tokens, and corrupt coords,
  and evaluate the active unit live (`CanInspect`, `CheckInteractDistance`,
  `UnitDistanceSquared` yardage, and cache freshness).
- **the 0.8.7 diag could still lie (0.8.8).** The report skipped the entire
  inspect-frame block whenever the event counters were zero -- which is the
  state right after /reload -- rendered "teardowns by reason" from pairs() so
  two reports of one state never matched, recorded `portraitSetFailed` and both
  anchor-bypass counters without ever printing them, had no per-section
  containment (one raising field killed every section after it), carried no
  verdict and no session uptime, and its tests matched substrings only.
  **the fix:** collector/renderer split, verdict first, fixed section order,
  per-section pcall in collection and rendering, deterministic sort, explicit
  caps, and structural pins.
- **an audit reporting an absence it could not verify.** a reviewer without
  access to the mirror asserted a client API did not exist when it was proven
  in game. **the fix:** an absence claim needs a whole-tree mirror sweep AND
  generated API docs; without them it is ASSUMED.
- **"checked all clients" without the operator's branch.** testing against
  clean branches missed that the operator's specific client branch lacked an
  `OnShow` on `GameTooltip`. **the fix:** verify against the operator's exact
  client branch first.
- **packaging failures on unignored tooling dotfiles.** Tracked configuration
  files like `.wowluarc.json` without `export-ignore` in `.gitattributes` cause
  release package verifiers to fail. **the fix:** keep `.gitattributes`
  synchronized with all tracked non-runtime files.

**when to signal `blocked`:** when the only way forward is a decision the
operator must make (a version to hold, a value to change, a feature to drop).
**when to signal `hands-up`:** when two desks disagree and the client source
cannot settle it. **when neither applies:** proceed with the defensible
default, note it in the journal, and keep going — that is what `guarded()`
and the `checkpoint` signal are for.

### 5. Dispatch, audit and helper process (2026-11-10)

- **a task graph with no dependencies runs flat.** every task dispatches at once, including review and
  release gates, which then run against unmodified code and report a meaningless PASS. dependencies must
  be attached when the tasks are created, or by an `update_task` that lands **before** dispatch — a task
  that has started cannot be edited, so the only repair is a new chained set of tasks.
- **one model route is a single point of failure.** three consecutive `429 RATE_LIMIT` killed the first
  attempt at the contract ledger. retrying the same task on the same route only burns attempts; check what
  routes actually exist before promising a fallback, and if there is only one, say so instead of offering
  a migration that cannot happen.
- **suppressing a diagnostic is not a fix.** `---@diagnostic disable-next-line` hides the report, not the
  hazard. when the analyzer cannot narrow a guard, restructure the guard — an early return, or the test in
  its own `if` — rather than silence it. if a pre-existing suppression blocks a gate, fix the gate.
- **a file in the linter's `library` set has no linter coverage.** its diagnostics are suppressed, so
  "0 findings" there means "not checked"; evidence for such a file must be a manual row audit.

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
