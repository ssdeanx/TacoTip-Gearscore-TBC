# Blizzard API verification — playbook (`wow-ui-source`)

- **subject:** how to settle any "does this API exist, and does it behave this way
  on client X?" question against the Blizzard FrameXML mirror — with evidence
- **date:** 2026-10-14
- **author:** `api-verification` desk
- **anchored to:** `/home/sam/wow-ui-source` at the branch versions in the table
  below; add-on claims anchored to `5bc83b7` + dirty tree
- **status:** VERIFIED (each item names its branch + path)
- **supersedes:** nothing

## why this exists

The add-on targets **five client families whose APIs genuinely differ**, and its
worst bugs have been API assumptions rather than logic errors: a distance helper
that read a global documented on none of the five clients, a range flag that is
undocumented but used by Blizzard itself, and a distance call whose second return
value decides whether the number means anything.

This is the procedure that converts an assumption into evidence, plus the four
findings it has already produced.

## scope

**In:** the mirror at `/home/sam/wow-ui-source` (read-only), the client → branch
map, the three kinds of evidence, worked examples, and the pitfalls that produce
false confidence.

**Out:** running the game (the operator does that), and any code change — this
desk produces the *claim*; the owning desk writes the code.

## the mirror (VERIFIED 2026-10-14)

- `origin` = `https://github.com/Gethe/wow-ui-source.git` — a mirror of the
  Blizzard-authored FrameXML + SharedXML that ships inside each client.
- **Treat it as read-only.** Read it with refs; never `git checkout` or edit it:
  `git --no-pager show <ref>:<path>`, `git grep <ref>`, `git ls-tree <ref>`.
- Root index: `SKILL.md`; branch/architecture notes in `reference/`
  (`VERSION_BRANCHES.md`, `FILE_RESPONSIBILITY.md`, `API_NAMESPACES.md`,
  `ARCHITECTURE.md`); each branch carries `version.txt`.

### client → branch map for this add-on (VERIFIED, read from each branch)

| our client | interface | branch | version at 2026-10-14 |
|---|---|---|---|
| Classic Era / SoD | `11509` | `origin/classic_era` | `1.15.9.70003` |
| TBC Anniversary | `20506` | `origin/classic_anniversary` | `2.5.6.70006` |
| Titanforge (Wrath) | `38002` | `origin/classic_titan` | `3.80.2.70315` |
| WoW Forever | `16001` | `origin/forever` | `1.60.1.70374` |
| Retail | `120100` | `origin/live` | `12.1.5.70391` |

`origin/classic` (`5.5.4`) is a *different* line from `classic_era`, and
`origin/ptr` is the retail test realm: both are interesting for "what is coming",
never for "what our users run". When a branch's `version.txt` predates the patch
our users are on, the mirror is stale — say so, or `git fetch` (needs network).

## the procedure

1. **Name the question so it can be wrong.** "Does `X` exist" is weak; "does
   `NotifyInspect` refuse a unit 40 yards away, and does it raise or return" is
   answerable.
2. **Pick the branch** from the table (one per client we ship).
3. **Find Blizzard's own call sites first — strongest evidence:**
   ```bash
   cd /home/sam/wow-ui-source
   git grep -n "NotifyInspect(" origin/classic_era -- '*.lua'
   git grep -n "CheckInteractDistance" origin/classic_era -- '*.lua'
   ```
4. **Then read the generated documentation** for the published signature:
   `Interface/AddOns/Blizzard_APIDocumentationGenerated/<Area>Documentation.lua`
   (535 such files on `classic_era`).
5. **When they disagree, the call site wins** — the engine is what runs. Record
   *both* in the answer, because the disagreement is the useful part.
6. **Repeat across every branch we ship** when the behaviour is family-sensitive.
   The classic branches keep per-family subfolders (`Vanilla/`, `TBC/`, `Wrath/`
   under e.g. `Blizzard_InspectUI`, `Blizzard_UnitPopup`) — read the one your
   client uses.
7. **Cite it**: branch + path + line + date, in the code comment, the test, or the
   desk journal. Line numbers drift with the mirror; branch + version pin them.

## findings this procedure has produced (all VERIFIED)

1. **`CanInspect` — the undocumented second argument is real.** The generated doc
   (`origin/classic_era:…/Blizzard_APIDocumentationGenerated/PlayerScriptDocumentation.lua`)
   lists a single `targetGUID` argument, but Blizzard's own inspect flow calls
   `CanInspect(unit, true)` (`…/Blizzard_InspectUI/Vanilla/Blizzard_InspectUI.lua`
   and the `TBC/` copy, `InspectFrame_Show`). Consequence for us: on the classic
   family, the range flag cannot be treated as a documented contract, which is why
   `LibForeverInspector.requestInspect` also checks
   `CheckInteractDistance(unit, 1)` at the choke point.
2. **`CheckInteractDistance(unit, distIndex)` — what the indices are.** Blizzard's
   unit popups gate their own buttons with it
   (`…/Blizzard_UnitPopupShared/UnitPopupSharedButtonMixins.lua`: trade `2`, duel
   `3`, follow `4`; base returns `nil`), consumed by
   `UnitPopupSharedUtil.IsEnabled` (`…/UnitPopupSharedUtils.lua`). Index `1` is
   the inspect-range class — the assumption behind
   `INSPECT_INTERACT_DISTANCE_INDEX = 1`.
3. **`UnitDistanceSquared` returns `(distance, checkedDistance)`**, and the flag
   decides whether the number may be trusted: Blizzard's own consumer only uses
   it when `checkedDistance` is true
   (`…/Blizzard_UnitFrame/Shared/CompactUnitFrame.lua`,
   `CompactUnitFrame_UpdateDistance`), and it compares the **squared** value.
   `LibForeverInspector.inspectDistanceSquared` matches that, which is why an
   unmeasurable unit falls through to `CheckInteractDistance` instead of being
   refused or blindly asked.
4. **Absence in the mirror is not evidence of absence.** The range-refusal error
   text (`Not in Range` / `Can't Inspect`) appears **nowhere** in the checkout —
   it is an engine string, not FrameXML. A session that greps, finds nothing, and
   concludes the error does not exist will "fix" the wrong layer. Range refusal is
   only observable in-game, which is why the desks carry an in-game checklist.

## pitfalls

- **`inherits` is transitive, so grep cannot answer "does this frame have method
  X".** Walk the chain to the root and check `mixin=` at each level, or read the
  element with `git show origin/<branch>:<path>` (the short version of this is in
  `AGENTS.md` → *Reading Blizzard's XML*, which also records that grepping
  `<On[A-Za-z]+>` misses every `<OnHide function="...">` form — that pattern
  produced a script table that "looked plausible and was wrong").
- **`git grep` counts call sites, not definitions.** A hit proves Blizzard *uses*
  a name, never that it exists on the branch you are reading.
- **An `origin/`-qualified ref is required.** A bare `forever` or `classic`
  silently returns nothing and looks exactly like an absence.
- **Engine strings and engine errors are invisible here.** Anything the client's
  C++ raises or prints (UI errors, some coercions, protected-call rules) will not
  appear in a grep. Say `UNKNOWN`, then test in-game.
- **Generated docs are metadata, not behaviour.** They omit optional arguments
  (see finding 1) and say nothing about raise-vs-return.
- **Per-family subfolders.** The same logical file exists three times on the
  classic branches; reading `Wrath/` and calling it "classic" is how a
  Wrath-only assumption reaches a Classic Era user.
- **Bound every command.** `git grep` over a whole branch is huge: use `-n`, `-l`,
  `-- '*.lua'`, and `| head`. Save output to a file rather than dumping it.
- **Never mutate the mirror.** It is the shared evidence; a local edit destroys
  the audit trail for every desk.

## routing

Bring a question here when it touches **any Blizzard API call, hook/driver
choice, client-family branch, event, or error path** — and especially when the
current evidence is "it worked on my client". The desk answers with a citation;
the owning desk writes the code and the test.
