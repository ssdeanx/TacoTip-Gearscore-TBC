# workshop

where things live, and which skill to load before touching them. detail lives
in the linked files, not here.

## map

| path | role |
|---|---|
| `CAIRN.md` | disposition, evidence vocabulary, precedence ladder |
| `hands-up.md` | escalation procedure — when each signal fires |
| `desks/` | one desk per workstream; each owns a `journal.md`, its memory. start at `desks/README.md` |
| `bench/` | shared workspace: findings, verdicts, drafts, reports. start at `bench/README.md` |
| repo root | the shipped addon itself — `TacoTip.toc`, `main.lua`, `gearscore.lua`, `pawn.lua`, `textures.lua`, `options.lua`, `Locale/`, `Libs/` |

blizzard truth lives outside the repo at `/home/sam/wow-ui-source`, one
`origin/`-qualified branch per client. it is the only acceptable source for
api claims.

## the invariants — do not touch

not style choices. each one has a release behind it.

- **the classic era inspect range gate** — `NEARBY_ASK_YARDS` 20/40,
  `INSPECT_INTERACT_DISTANCE_INDEX` 1, distance-first ordering, the probe
  guard, the learned ceiling, every timing constant. 0.8.3 exists because a
  range regression popped "not in range" at 10k players.
- **the gearscore formula** — the A/B/C tables, `Scale`, `QualityScale`,
  `ITEM_BAND_SCALE`, every `SlotMOD`, the hunter factors, titan grip. the
  numbers are the product.
- **the retail bracket** — held at the shared 1000 by operator decision.
- **the wire format** — `R;2` plus `G`/`D`, 13 fields, the 240-byte door.
- **the saved-variables shapes** — `TacoTipConfig`, `TacoTipExtrasDB`.
- **`CanInspect` is called with ONE argument.** the second argument is
  `showError`: it makes the engine display a message. that is the popup 0.8.3
  removed.
- **no invented translations.** a name you cannot source is left alone and
  reported.
- **`_G.PlaySound` is NEVER replaced or detoured.** Detouring `PlaySound`
  taints `GameMenuFrame` and triggers `ADDON_ACTION_FORBIDDEN` calling `UNKNOWN()`
  when the player clicks "Exit Game" or "Logout" on Classic Era. Out-of-range
  inspect sounds are suppressed at `GetGameMessageInfo` inside
  `UIErrorsMixin:TryDisplayMessage`.
- **container item buttons are strictly excluded from default tooltip re-anchoring.**
  Blizzard's `ContainerFrameItemButton_CalculateItemTooltipAnchors` does NOT
  call `ClearAllPoints()`. If `onGameTooltipSetDefaultAnchor` pins `GameTooltip`
  to `TacoTipDragButton`, bag items get dual anchors, causing the tooltip to
  stretch across the display or collapse off-screen.
- **do not cache incomplete inspect gear.** When `GetInventoryItemTexture` is
  non-nil but `GetInventoryItemLink` is nil, item data is still in-flight from
  the server. Never write `data.time = now` or finalize GearScore prematurely;
  retry asynchronously (250ms) until links resolve.
- the extras' whisper path stays deleted. the guild/level line-index
  ownership proof stays as it is, and the inspect-frame guild guard stays
  installed — both are explained in
  `bench/audits/2026-10-20-inspect-and-guild-line-history.md`.

## what the client actually does

facts worth not re-deriving. all verified against the mirror or the client db
during the 0.8.4 release.

- **slash dispatch takes ONE token.** the client splits the typed text at the
  first whitespace (`ChatFrameEditBox.lua`: `strmatch(text, "^(/[^%s]+)")`), so
  `/tt lb` is dispatched as `/TT` with the argument `lb`. there is no prefix
  scan and no ordering race.
- **`SlashCmdList` is a proxy, and it is wiped before every dispatch.**
  `ChatFrameSetup.lua` gives it a metatable whose `__index` holds the handlers;
  `ChatFrameUtil.lua`'s `ImportListToHash` moves each handler there and then
  wipes the real table. **at dispatch time the real table is empty**, so
  `rawget(SlashCmdList, "NAME")` is always nil. use normal indexing, read the
  proxy's `__index`, or publish a plain global. the proxy's `__index` is keyed by
  the list name (`TACOTIPRANKS`); the dispatch hash is keyed by the uppercased
  alias (`/TT`).
- **a created frame is VISIBLE.** blizzard's own panels carry `hidden="true"`
  on the frame, not on the template chain. `CharacterFrame` and `InspectFrame`
  are hidden by default (their `OnShow` fires); `PaperDollFrame` and
  `InspectPaperDollFrame` are not (an `OnShow` hook on them NEVER fires).
- **a plain frame has no backdrop API.** `SetBackdrop` /
  `SetBackdropColor` / `SetBackdropBorderColor` exist only on
  `BackdropTemplate` or `BackdropTemplateMixin` frames. a frame created as
  `CreateFrame("Frame", …)` has none, and the `if f.SetBackdrop then` guard
  skips the backdrop silently.
- **`GameTooltip.FadeOut` is an ENGINE method and it is present on all five
  clients.** there is no Lua definition on any branch (whole-tree sweep) —
  blizzard calls it unguarded: the classic family at
  `Blizzard_UnitFrame/Classic/UnitFrame.lua:447` (`UnitFrame_OnLeave`),
  `origin/forever` `Mainline/UnitFrame.lua:393`, `origin/live` `:386`. it is
  absent from the generated api docs, so `type(GameTooltip.FadeOut) ==
  "function"` is TRUE at runtime on every client. (the earlier "only on live
  and forever" claim in this file was wrong.)
- **`SetPortraitZoom` is a real client API** on the CharacterModelBase
  template (`FrameAPICharacterModelBaseDocumentation.lua`), and blizzard calls
  it itself (`ModelFrames.lua`, `ModelFrameMixin.lua`). a bigger zoom value
  means a closer camera.
- **the classic-family unit tooltip is not the modern one.** it has no
  `GetUnit`, no `TooltipUtil` and no `owner.unit`; blizzard identifies it with
  `IsUnit` (`origin/classic_era` `GameTooltip.lua:498-503`). so any code that
  asks "is this a unit tooltip?" through the modern APIs alone reads a classic
  tooltip as something else — the 0.8.4 anchor gate did exactly that, and the
  saved tooltip position stopped applying on classic era.
- **the classic-family `GameTooltip` frame declares no `OnShow`.** its whole
  `<Scripts>` block is `OnLoad`, `OnTooltipSetUnit`, `OnTooltipSetItem`,
  `OnTooltipSetSpell`, `OnHide`, `OnUpdate`
  (`origin/classic_era` and `origin/classic_anniversary`
  `Blizzard_GameTooltip/Classic/GameTooltip.xml:20-31`). the two `<OnShow>`
  blocks in that file belong to `ShoppingTooltipTemplate` and
  `SmallTextTooltip`, **not** to `GameTooltip` — so a layer that has to run
  after the frame is laid out cannot use `OnShow` on the classic family. the
  modern pair is the opposite: `Mainline/GameTooltip.xml` declares `OnShow` on
  the frame itself (`GameTooltip_OnShow`, then `GameTooltip_CalculatePadding`).
  a `HasScript("OnShow")` guard is therefore correct and installs different
  layers on different clients — which has to be stated when a fix is claimed.
- **`GameTooltip_SetDefaultAnchor` is byte-identical on `classic_era` and
  `classic_anniversary`, and it does not anchor to the owner.**
  `tooltip:SetOwner(parent, "ANCHOR_NONE")`, then an explicit
  `SetPoint("BOTTOMRIGHT", "UIParent", "BOTTOMRIGHT", -CONTAINER_OFFSET_X - 13, CONTAINER_OFFSET_Y)`,
  then `tooltip.default = 1` (`GameTooltip.lua:109-114` on both branches). the
  `parent` is only the owner — the position is the screen corner. so "the
  tooltip is beside the frame" is never true on the classic family; it is
  bottom-right of `UIParent` or wherever the add-on puts it.
- **the client re-drives a unit tooltip on a timer.** `GameTooltip_OnUpdate`
  calls `owner:UpdateTooltip()`, else `self.UpdateTooltip()`, every
  `TOOLTIP_UPDATE_TIME`; a unit frame's `UnitFrame_UpdateTooltip` is
  `GameTooltip_SetDefaultAnchor(GameTooltip, self)` followed by
  `GameTooltip:SetUnit(self.unit, self.hideStatusOnTooltip)`
  (`origin/classic_anniversary` `Blizzard_UnitFrame/Classic/UnitFrame.lua`).
  on a unit frame the client therefore re-anchors **and** re-renders once a
  tick for as long as the mouse rests: a per-render decision is remade
  repeatedly, and anything the render must not undo has to survive that.
- **`SetWordWrap` / `SetNonSpaceWrap` and `C_Timer.NewTimer` exist on all five
  branches.** `SimpleFontStringAPIDocumentation.lua:551,666` and
  `UITimerDocumentation.lua:37`, verified on `classic_era`,
  `classic_anniversary`, `classic_titan`, `origin/forever` and `live`. two
  consequences: a FontString narrowed with `SetWidth` shortens a line only if
  wrap is on (otherwise the line's required width is still the full text), and
  "this client has no timer" is never a reason to skip a post-layout pass.
- **`forever` is remotes-only in the mirror.** there is no local `forever`
  branch; use `remotes/origin/forever`. `git show forever:…` fails with
  "Needed a single revision", which reads like a missing file and is not.
- **the game menu's Logout/Quit callback calls the client's global `PlaySound`
  immediately before the protected `Logout()`/`Quit()`.** five clients, five
  answers: `classic_era` `GameMenuFrame.lua:67` → `:69`; `classic_anniversary`
  `:67` → `:69`; `classic_titan` `:95` → `:97`; `forever` `:166` → `:168`;
  `live` `:118` → `:120`. (classic_era and classic_anniversary carry
  byte-identical file content — that is a fact about the FILES, not proof the
  two clients behave alike.) **a global the game menu calls must never be
  replaced by an add-on**: the protected call two lines later runs in a tainted
  context and is refused — `ADDON_ACTION_FORBIDDEN`, and the reporter can only
  name the engine function `'UNKNOWN()'`.
- **`securecall` is the containment primitive, and a `hooksecurefunc` post-hook
  is NOT a taint boundary.** `securecall` is an engine global on every client —
  `local securecall = securecall;` appears 7× on each of the five branches,
  and the call sites number 171 (classic_era), 171 (classic_anniversary), 171
  (classic_titan), 121 (forever), 120 (live). blizzard uses it for exactly
  this shape (`Blizzard_BuffFrame/BuffFrame.lua:991`
  `securecall(self.UpdateDuration, self, self.timeLeft); -- Taint issue with
  SecondsToTimeAbbrev`; `Blizzard_CatalogShop_Outbound.lua:17`
  `securecall("GameTooltip_Hide");`). a `hooksecurefunc` post-hook does not
  replace the hooked function, but its **body** still runs as addon code
  inside the caller's script chain — so addon code that enters a blizzard
  frame's script chain has to be wrapped, whichever hook installed it.
- **the client's own error path reads the sound kit id from
  `GetGameMessageInfo`.** `UIErrorsMixin:TryDisplayMessage`
  (`origin/classic_era` `UIErrorsFrame.lua:140-149`; `origin/live` and
  `origin/forever` `UIErrorsFrame/Mainline/UIErrorsFrame.lua:150`) adds the
  message first, then reads
  `errorStringId, soundKitID, voiceID = GetGameMessageInfo(messageType)` and
  plays the voice or the sound kit. call sites per branch: 2 (classic_era), 2
  (classic_anniversary), 2 (classic_titan), **3** (forever — two `VoiceUtils`
  files, `Classic/:82` and `Mainline/:88`), 2 (live) — and **none of them is
  on the game menu's path on any branch**, which is what makes it the safe
  place to mute a refusal's sound.
- **an XML child named `$parentX` inside a frame named `F` becomes the
  global `FX`.** the classic chain declares the tooltip's status bar as
  `<StatusBar name="$parentStatusBar" .../>` inside `GameTooltipTemplate`
  (`origin/classic_era` `Blizzard_SharedXML/Classic/GameTooltipTemplate.xml:138`)
  and the modern chain as `<StatusBar parentKey="StatusBar"
  name="$parentStatusBar" .../>` (`origin/forever` and `origin/live`
  `Blizzard_GameTooltip/Mainline/GameTooltip.xml:9`) — so the global
  **`GameTooltipStatusBar` EXISTS on all five clients** and any hook on it is
  an always-on hook into a blizzard frame's script chain. the same rule gives
  `GameTooltipTextLeft1` from `$parentTextLeft1`, which this add-on already
  depends on. **a grep for the identifier alone is not a proof of absence
  here**: the tree spells it `$parentStatusBar`.
- **the shared GameTooltip reaches a NineSlice child on all five clients**,
  and `SetBackdrop` is absent on all five (it belongs to
  `BackdropTemplateMixin`, which no tooltip chain mixes in). the classic chain
  reaches the NineSlice through `GameTooltipTemplate` ->
  `TooltipBackdropTemplate` -> `TooltipBackdropTemplateMixin` and adds
  `SetBackdropColor` / `SetBackdropBorderColor`; forever and retail reach it
  through `SharedTooltipTemplate` -> `SharedTooltipArtTemplate` and expose
  neither. the add-on's own in-game suite records this
  (`Tests/TacoTip_Forever_Tests.lua` → `BackdropTemplateContract`), and the
  legacy no-NineSlice graft in `main.lua` is therefore dead on every client.
- **`GetGameMessageInfo` is the safe sound suppression boundary on Classic Era.**
  Blizzard's `UIErrorsMixin:TryDisplayMessage` calls
  `local errorStringId, soundKitID, voiceID = GetGameMessageInfo(messageType)`
  right before playing the sound kit. Returning `soundKitID = nil` for
  `ERR_OUT_OF_RANGE` stops the error sound without replacing `PlaySound` or
  tainting `GameMenuFrame`.
- **`GetMouseFoci()` returns an empty table `{}` in 3D world space on modern engines.**
  On TBC Anniversary, Retail, and Forever, hovering over 3D world units returns an
  empty table from `GetMouseFoci()`. `TT:GetMouseFocus()` must check for an
  empty list and fall back to `WorldFrame`, otherwise `frames[1]` evaluates to `nil`.
- **`GetInventoryItemTexture` exists and is non-nil before `GetInventoryItemLink` on fresh inspects.**
  When `INSPECT_READY` fires, the client engine may have loaded the icon texture
  before the full item link string has returned from the server. Checking
  `GetInventoryItemTexture(unit, slot)` identifies equipped items whose links
  are still resolving asynchronously, avoiding premature 5-minute caching of
  partial GearScores (such as GS 104).
- **tracked tooling dotfiles require explicit `export-ignore` rules.**
  Any newly tracked development or tooling files (e.g. `.wowluarc.json`,
  `/.ruff_cache/**`) must be marked `export-ignore` in `.gitattributes`, or
  `Tools/verify_release.sh --worktree` will fail on the runtime allowlist check.

## how to check a client string the mirror does not carry

the mirror is **english-only FrameXML** — it has no client locale strings, and
its stat tables are engine-side. for a localized string, read the client's own
database:

    https://wago.tools/db2/<Table>/csv?build=<build>&locale=<locale>

e.g. `ChrSpecialization` for specialization names, `ChrClasses` for class
names. the csv gives the client rows with `OrderIndex`, which is what proves a
name lines up with the english table's index. that is how the russian monk /
demon hunter / evoker names were confirmed. cross-check against blizzard's own
localized pages (`worldofwarcraft.blizzard.com/ru-ru/game/classes/…`) or
wowhead's locale (`/ru/talent-calc/<class>/<spec>`) before trusting a row.

## how to check the package you are shipping

the release verifiers read the **working tree**, not the last commit:

    bash Tools/verify_release.sh --worktree
    bash Tools/verify_release_extras.sh --worktree

they print the exact file list of each package and fail on anything that should
not ship (workshop docs, tests, lint config, PNGs). run them before a package
leaves the machine — `git archive HEAD` validates a commit you are not
shipping.

## how to run a lane

these are the rules that were learned the hard way on the 0.8.4 release, when
five hours were lost to lanes colliding on the same files.

1. **one lane, one complete task.** give a lane the whole task up front, with
   every constraint, every file it may touch, and the validation bar. do not
   send a chain of corrections to a running lane, and never let two
   instructions contradict each other. if a brief turns out to contain a wrong
   assumption, the fix is a fresh, complete brief — not another message.
2. **every lane uses the skills.** `@desk-open` (its own desk), `@desk-journal`
   (each step), `@bench-read` (prior findings, as leads only), `@signal-write`
   (one `done` signal when it lands). a lane that skips them works blind: it
   does not know what the last lane changed, cannot see the prior audits, and
   leaves no trail for the next one.
3. **the desk is the hand-off.** a lane that owns files writes its `done`
   signal when the tree is green; the next lane waits for that signal and
   re-reads every file immediately before editing it. lanes that overlap on
   files must be sequenced by signal, never by guesswork.
4. **verify by reading the code and by the suites.** do not verify with
   hashes or digests of files, do not browse the web, and do not add new
   files unless asked. **a pin that cannot go red is not a test:** assert a
   literal or an independent derivation, never a copy of the value under test,
   and show every new pin going red on a copy before it is accepted.
5. **the operator's in-game observation beats any audit.** when he says a
   feature works, that is the fact; check the client api in the mirror before
   "fixing" something that is not broken.
6. **the tooltip mover is ONE mechanism — read it end to end before you
   touch any part of it.** `TacoTipDragButton`, `TacoTipConfig.custom_pos` /
   `custom_anchor`, the `GameTooltip_SetDefaultAnchor` post-hook and
   `isManagedAnchorTarget` are a single mechanism: the dot carries the
   tooltip, the hook re-anchors it, the drag-stop handler saves it. 0.8.4
   added a gate to that hook and the saved position stopped applying on
   classic era; the operator found it in game. the same rule covers every
   other mechanism here: **read what it does before you change it**, and if
   you cannot say in one sentence what the change does to the player's
   experience, do not make it.
7. **never guess, never assume, and never act outside the brief.** an
   instruction you were not given is not yours to execute: a value the operator
   did not ask for, a file nobody assigned you, a fix you inferred from a
   symptom. **guessing, assuming, or acting outside the brief ends the lane —
   the operator terminates it on the spot.** this is an enterprise-grade
   release: an inferred change to shipped behaviour is a defect, not a
   contribution. when the brief is wrong, stop and say so.
8. **the operator's branch is checked first.** before any client claim, read the
   branch the operator plays (`classic_anniversary` on TBC) and the one they can
   observe (`classic_era`). a claim that has not passed those two is not a
   claim, and "all five pass" in a suite is not the same statement — the suite
   proves the code runs, not that the player-visible result is right.


## skill index

| skill | load it when |
|---|---|
| skill `desk-open` (skill tool) | before opening a desk or sitting at one — new name vs live journal check |
| skill `desk-journal` (skill tool) | before writing or closing any `desks/<name>/journal.md` entry |
| skill `bench-read` (skill tool) | before reading or adding any `bench/` artifact |
| skill `signal-write` (skill tool) | before emitting any `desks/<name>/.signals/*.json` — see `hands-up.md` |
