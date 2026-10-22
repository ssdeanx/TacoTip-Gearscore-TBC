# fix-anchor-unit-gate — Journal

## 2026-10-22 — Desk opened
- **Purpose:** Scope the `GameTooltip_SetDefaultAnchor` post-hook's `custom_pos` re-pin to unit hovers only, so bag/item and addon surfaces keep their caller-set anchor while the operator's confirmed unit re-hover fix stays intact.
- **Scope:** `main.lua` `onGameTooltipSetDefaultAnchor` only + `Tests/harness/tooltip_test.lua` pins. No other files.
- **Context:** `dad58ec` restored the 0.8.3 unconditional re-pin; operator confirmed unit re-hover fixed in game; now reports bag hover broken and other tooltip-using addons unhappy. Bench: `audit-anchor-fix.md` §5 already documented item/panel/addon surfaces firing SetDefaultAnchor and receiving the pin.
- **Next step:** Step 1 — mirror investigation of bag/item/world-mouseover call sites on `origin/classic_anniversary` before any edit.

## 2026-10-22 — Step 1 evidence (mirror: `origin/classic_anniversary`, read-only)

**1a. Hook shape.** `main.lua:4028-4108`; gate `isManagedAnchorTarget` `3931-4026`
probes TooltipUtil.GetDisplayedUnit → tooltip.GetUnit → owner.unit → parent.unit
(all `UnitExists`) → `IsUnit(mouseover/target/player/focus)`; no signal → `"menu"`.
`db275d7` added the gate incl. the `parent.unit` / `IsUnit` probes; `dad58ec`
replaced the bare `return` in the skip with
`if (TacoTipConfig.anchor_mouse or not TacoTipConfig.custom_pos) then return end`.

**1b. Call sites.**
- Bag items DO NOT call `GameTooltip_SetDefaultAnchor`:
  `ContainerFrameItemButton_OnEnter` = `SetOwner(self, "ANCHOR_NONE")` then
  `ContainerFrameItemButton_CalculateItemTooltipAnchors` SetPoints straight to the
  button (`Blizzard_UIPanels_Game/Classic/ContainerFrame_Shared.lua:1400-1402`,
  point logic `:1379-1398`). Bag buttons carry no `.unit`.
- Unit frames DO: `UnitFrame_UpdateTooltip` → `GameTooltip_SetDefaultAnchor(GameTooltip, self)`
  with `self.unit` (`Blizzard_UnitFrame/Classic/UnitFrame.lua:451-452`; newbie path `:430/:434`).
- Panel/item sites pass unitless frames: `PaperDollFrame.lua:2249`, `ActionButton.lua:1104`,
  QuestLog/PVP/Honor/Minimap, `GameTooltipTemplate.lua:13`.

**1c. World mouseover ROUTES through the hook, menu-classified, unitless parent — quoted:**
- `origin/classic_anniversary:Interface/AddOns/Blizzard_SharedXML/Classic/GameTooltipTemplate.xml:153`
  `<OnTooltipSetDefaultAnchor method="OnTooltipSetDefaultAnchor"/>` + `GameTooltipTemplate.lua:12-14`
  `function GameTooltipMixin:OnTooltipSetDefaultAnchor() GameTooltip_SetDefaultAnchor(self, UIParent); end`
  → engine-fired script ⇒ parent = `UIParent` (no `.unit`).
- No FrameXML/world-mouseover Lua call site exists (grep, 69 sites, none world).
- Addon's own client truth, `main.lua:1471-1479`: "the client calls
  GameTooltip_SetDefaultAnchor(GameTooltip, self) IMMEDIATELY BEFORE
  GameTooltip:SetUnit(...) ... **A world/mouseover unit therefore reads as
  "menu", the hook returns untouched, and the tooltip stays where the client
  put it -- the bottom-right corner. That is the "it resets my position" report.**"
  ⇒ world mouseover executes the post-hook, gate reads `"menu"` (parent=UIParent,
  residue cleared by SetOwner), and that skip WAS the pre-dad58ec report.
- Corroboration: wowinterface t=59029 — `OnTooltipSetDefaultAnchor` "the only
  GameTooltip handler that would fire for tooltips that are not associated with
  an item or unit" (engine-generated world tooltips).

**Decision (per brief: Step 1c showed it routes ⇒ add the mouseover case, do not stop):**
the fall-through re-pin keeps two unit shapes and blocks everything else:
1. `managedAnchor` true (unit frames via `parent.unit`, residue-unit tooltips) — unchanged;
2. fall-through remainder ⇒ pin ONLY the world-mouseover shape:
   `TT:GetMouseFocus() == WorldFrame` AND `UnitExists("mouseover")`
   (the codebase's own world test, `main.lua:4083` idiom).
Bags/panels/addons/menus arrive with the cursor ON THEIR OWN FRAME ⇒ pass through
(0.8.4 "menu passes through by design" contract), counters still tally first.
A `parent.unit`-only discriminator was rejected: world mouseover (parent=UIParent,
empty residue) would lose the pin and revert the operator's accepted fix.
Mouse focus separates world hover from bag hover even when both arrive via the
mixin with parent=UIParent — identical frame args, different cursor target.

## 2026-10-22 — [signal:done] Unit gate shipped on the fall-through — pinned in the harness, not observed in game

**Diff (working tree, NOT committed):** `main.lua` +49/−2,
`Tests/harness/tooltip_test.lua` +69/−10 — hook + tests only; `git status` shows
nothing else (`Screenshot_20261021_191927.png` and `desks/` pre-existing untracked).

**Fix (Step 2):** new `isWorldMouseoverUnitHover()` helper
(`main.lua:4044` region) + gate in the `not managedAnchor` fall-through:
after the dad58ec condition and the still-tallying counters, return unless
`TT:GetMouseFocus() == WorldFrame` AND `UnitExists("mouseover")` (nil-WorldFrame
guarded). Managed unit frames (`parent.unit`/`owner.unit`/`IsUnit`) unchanged;
anchor_mouse / anchor_mouse_spells / custom_pos-nil branches, counters, render-time
`applyCustomTooltipAnchor`, runUntainted registration byte-untouched.

**Pins (Step 3):** re-hover pins A/B kept parent=UIParent (the mixin world shape —
main.lua:1471-1479's documented menu-classified unit hover) and now seed focus =
WorldFrame via a new `seedFocus` helper (`GetMouseFoci` save/restore added);
parent={unit="target"} was deliberately NOT used — it would route the pin through
the managed path and could no longer go red under the pre-fix revert.
NEW pin C: bag-like unitless parent + cursor on that button (live stale
mouseover kept alive) → caller's park survives: exactly one point, BOTTOMRIGHT,
no hook SetPoint, no ClearAllPoints.

**Validation (Step 4, exact):**
- `bash Tests/harness/run_all.sh` → **TOTAL 71 invocations: 71 passed, 0 failed**
- `LUA=lua5.4 …` → **71/71**; `LUA=luajit …` → **71/71**
  (anomaly, disclosed: the FIRST luajit run reported `failed: tooltip_test
  CLASSIC_ERA` while running concurrently with the two verify scripts; that run's
  detail was lost to `tail` — 7 subsequent full luajit runs + 30 standalone
  repeats of that exact invocation: 0 failures. My pins are pure/synchronous.)
- `luacheck .` → **0 warnings / 0 errors in 88 files**
- `Tools/verify_release.sh --worktree` → **PASS**; `Tools/verify_release_extras.sh --worktree` → **PASS**
- Per-pin revert proofs, own copy at `/tmp/opencode/unit-gate-revert` (deleted):
  - pre-dad58ec (comment+condition+gate → bare `return`): A/B RED ×5 families,
    `2/250 FAILED` (legacy) / `2/258` (pipeline):
    `FAIL re-hover with empty residue … relIsHandle=false point=BOTTOMRIGHT/BOTTOMRIGHT`
  - dad58ec (gate removed only): pin C RED ×5 families, `1/250` / `1/258`:
    `FAIL bag-like parent passes through … point=TOPLEFT setPointCalls=1 relIsHandle=true`
  - fixed tree: all green (250/258 per family = prior totals + 1 new pin)

**Pinned in the harness, not observed in game.** Operator acceptance = hover a bag
item and a unit re-hover on classic_anniversary: bag shows at its own anchor,
units (frame + world mouseover) still re-pin to the saved position.
