# AUDIT: the anchor-gate fix (`onGameTooltipSetDefaultAnchor` re-pin) — independent verification

- **Desk:** `audit-anchor-fix` — 2026-10-22. Independent audit lane. The fixer's
  claims were re-derived from the live tree, the client truth file and my own
  validation runs; nothing was taken on trust.
- **Trees:** AUDITED `/home/sam/TacoTip-Gearscore-TBC/` (TOC 0.8.4, HEAD
  `db275d7`, DIRTY — see §2) vs PRIOR WORKING `/home/sam/TacoTip/` (TOC 0.8.3,
  read-only).
- **Fix under audit (as claimed by desk `fix-anchor-gate`):** in
  `main.lua` `onGameTooltipSetDefaultAnchor` (~4064-4081), the
  `isManagedAnchorTarget` skip now counts `anchorSkippedMenu` /
  `anchorSkippedUnresolved` but returns early only when `anchor_mouse` is on OR
  `custom_pos` is nil; with `custom_pos` set it falls through to
  `ClearAllPoints` + `SetPoint(anchorPoint, TacoTipDragButton, anchorPoint)` on
  every hook call (0.8.3 behavior, `/home/sam/TacoTip/main.lua:2840-2842`).
  New pins in `Tests/harness/tooltip_test.lua`.
- **Verdict: AUDIT PASS** — every claim re-verified; both new pins proven
  fail-able (revert proof, all five families); tree green. **Pinned in the
  harness, not observed in game** — in-game acceptance remains the operator's
  hover on classic_anniversary.

Evidence labels per `CAIRN.md`: claims below are **VERIFIED** by the quoted
code/command output unless marked.

---

## 1. Code trace of the fixed loop (three paths) against the CURRENT tree

### 0. The hook body as it now stands — branch order, verbatim

`main.lua:4028-4108` (live), in execution order:

```lua
main.lua:4028: local function onGameTooltipSetDefaultAnchor(tooltip, parent)
main.lua:4029:     if (not tooltip) then
main.lua:4030:         return
main.lua:4031:     end
main.lua:4032:     if (isAddonAnchorFrame(parent) or isAddonAnchorFrame(tooltip)) then
main.lua:4033:         return
main.lua:4034:     end
main.lua:4035:     if (TacoTipConfig.anchor_mouse_spells) then
...            -- spell/action parent -> SetOwner(ANCHOR_LEFT/RIGHT) + return
main.lua:4055:         return
main.lua:4056:     end
main.lua:4064:     local managedAnchor, anchorSkipKind = isManagedAnchorTarget(tooltip, parent)
main.lua:4065:     if (not managedAnchor) then
main.lua:4066:         TT.ev = TT.ev or {}
main.lua:4067:         if (anchorSkipKind == "menu") then
main.lua:4068:             TT.ev.anchorSkippedMenu = (TT.ev.anchorSkippedMenu or 0) + 1
main.lua:4069:         elseif (anchorSkipKind == "unresolved") then
main.lua:4070:             TT.ev.anchorSkippedUnresolved = (TT.ev.anchorSkippedUnresolved or 0) + 1
main.lua:4071:         end
        -- [fix comment block, 7 lines]
main.lua:4078:         if (TacoTipConfig.anchor_mouse or not TacoTipConfig.custom_pos) then
main.lua:4079:             return
main.lua:4080:         end
main.lua:4081:     end
main.lua:4082:     if (TacoTipConfig.anchor_mouse) then
...            -- mouse-anchor branch (unchanged, 0.8.3 shape)
main.lua:4090:     else
main.lua:4091:         if (TacoTipConfig.custom_pos) then
main.lua:4092:             if (not TacoTipDragButton and TacoTip_CustomPosEnable) then
main.lua:4093:                 TacoTip_CustomPosEnable(false)
main.lua:4094:             end
main.lua:4095:             if (TacoTipDragButton) then
main.lua:4096:                 tooltip:ClearAllPoints()
main.lua:4097:                 local anchorPoint = TacoTipConfig.custom_anchor or "TOPLEFT"
main.lua:4098:                 tooltip:SetPoint(anchorPoint, TacoTipDragButton, anchorPoint)
main.lua:4099:             end
main.lua:4100:         elseif (TacoTipConfig.show_hp_bar and TacoTipConfig.show_power_bar) then
main.lua:4101:             tooltip:ClearAllPoints()
main.lua:4102:             tooltip:SetPoint("BOTTOMRIGHT", "UIParent", "BOTTOMRIGHT", -CONTAINER_OFFSET_X - 13, CONTAINER_OFFSET_Y + 9)
main.lua:4103:         end
main.lua:4104:     end
main.lua:4105:     if (tooltip.EnableMouse) then
main.lua:4106:         tooltip:EnableMouse(false)
main.lua:4107:     end
main.lua:4108: end
```

0.8.3 counterpart (`/home/sam/TacoTip/main.lua:2811-2852`): identical shape with
NO `isAddonAnchorFrame` guard, NO unit gate — the `custom_pos` pin at
`2835-2843` is reached on every call:

```lua
/home/sam/TacoTip/main.lua:2835:         if (TacoTipConfig.custom_pos) then
/home/sam/TacoTip/main.lua:2836:             if (not TacoTipDragButton and TacoTip_CustomPosEnable) then
/home/sam/TacoTip/main.lua:2837:                 TacoTip_CustomPosEnable(false)
/home/sam/TacoTip/main.lua:2838:             end
/home/sam/TacoTip/main.lua:2839:             if (TacoTipDragButton) then
/home/sam/TacoTip/main.lua:2840:                 tooltip:ClearAllPoints()
/home/sam/TacoTip/main.lua:2841:                 local anchorPoint = TacoTipConfig.custom_anchor or "TOPLEFT"
/home/sam/TacoTip/main.lua:2842:                 tooltip:SetPoint(anchorPoint, TacoTipDragButton, anchorPoint)
```

### a. Re-hover with empty residue — does the hook re-pin unconditionally when `custom_pos` is set? YES (VERIFIED)

Walk: mouse re-enters a unit frame → client `UnitFrame_UpdateTooltip` →
`GameTooltip_SetDefaultAnchor` (client body: `SetOwner(parent, "ANCHOR_NONE")`
+ `SetPoint("BOTTOMRIGHT", "UIParent", …)` + `default = 1` —
`origin/classic_anniversary` `Blizzard_GameTooltip/Classic/GameTooltip.lua:109-113`,
quoted in `bench/findings/anchor-client-truth.md` §(a)) → post-hook fires in the
same call.

Empty residue means the gate probes a tooltip whose lines/units were just reset
by `SetOwner`: `TooltipUtil.GetDisplayedUnit` nil (or absent on classic),
`GetUnit` nil, no `owner.unit`, `IsUnit` all false, `parent.unit` nil
(`main.lua:3955-4021`) → falls to `main.lua:4025: return false, "menu"`.

Then, live code:
- `main.lua:4068` — `anchorSkippedMenu` increments.
- `main.lua:4078` — `TacoTipConfig.anchor_mouse` is off and `custom_pos` is set
  → the condition is false → **no early return**.
- Falls through to `main.lua:4095-4098`:
  `tooltip:ClearAllPoints()` then
  `tooltip:SetPoint(anchorPoint, TacoTipDragButton, anchorPoint)` —
  **on EVERY hook call**, matching 0.8.3 `main.lua:2840-2842` hop for hop.

### b. Does any path still skip the re-pin while `custom_pos` is set? — the render path can skip; the hook cannot (VERIFIED)

Skip-classified calls in the hook now return before the pin only in these
cases, all by design and all matching the pre-fix or 0.8.3 intent:

1. `main.lua:4032-4034` — `isAddonAnchorFrame(parent) or isAddonAnchorFrame(tooltip)`:
   `main.lua:3916-3918` `return frame ~= nil and (frame == TacoTipDragButton or frame == TacoTipMouseAnchor)`
   — only the addon's OWN frames (drag handle, mouse anchor). Pre-existing
   committed 0.8.4 code, untouched by this fix (not in the fix diff hunk).
   The mover path owns that case (`ShowExample`, `main.lua:2544-2555`).
2. `main.lua:4035-4056` — spell/action parents with `anchor_mouse_spells` on:
   re-owned `ANCHOR_LEFT/RIGHT` and returned — byte-shape identical to 0.8.3
   `main.lua:2812-2824` (only the `GetParent` call is now pcall-guarded,
   committed pre-fix).
3. `main.lua:4078-4080` — `anchor_mouse` on OR `custom_pos` nil — the fix's own
   documented carve-out; the mouse mode and the nil mode keep the skip.

The **render path remains skippable** — `applyCustomTooltipAnchor`
(`main.lua:1484-1507`, called last at `main.lua:2009`) is never reached when
`onTooltipSetUnit` early-returns at `main.lua:2519-2520` (unresolved unit),
`main.lua:2623` (empty `text[1]`), or `main.lua:2624` (player with empty
`text[2]`), and `tooltip_delay` defers the render
(`main.lua:3335-3351`). **But that skippability no longer costs position:**
per the client truth file (`anchor-client-truth.md` §(b), VERIFIED against
`origin/classic_anniversary`), while a unit-frame hover is held the client
re-invokes `GameTooltip_SetDefaultAnchor` every ≤0.2 s
(`GameTooltip_OnUpdate` → `owner:UpdateTooltip()` = `UnitFrame_UpdateTooltip`
→ `SetDefaultAnchor` + `SetUnit`; `TOOLTIP_UPDATE_TIME = 0.2`). Each of those
calls runs the fixed hook in the SAME call stack as the client's bottom-right
park — pin applied before any frame is presented. For owners with no
`UpdateTooltip` (one-shot SetDefaultAnchor), the single call still runs the
hook. Between the hook's pin and the next render nothing else moves the
GameTooltip (render early-returns don't SetPoint; the client has no restore
call of its own). **No remaining window where a `custom_pos` hover sits at the
client park.**

### c. Multi-anchor smear — ClearAllPoints precedes SetPoint (VERIFIED)

`main.lua:4096-4098`: `tooltip:ClearAllPoints()` is executed immediately before
`tooltip:SetPoint(anchorPoint, TacoTipDragButton, anchorPoint)`, inside the
same branch, same call. Whatever anchors exist after the client's park
(`SetPoint("BOTTOMRIGHT", "UIParent", …)` — and `SetOwner`'s anchor semantics
are unprovable from the mirror, per `anchor-client-truth.md` §(c)) are removed
first, so a stale BOTTOMRIGHT can never coexist with the handle anchor.
Identical to 0.8.3 `main.lua:2840-2842`. The same guarantee holds on the
render-time path (`main.lua:1504-1505`).

### d. `anchor_mouse` / `anchor_mouse_spells` / `custom_pos` nil — unchanged (VERIFIED)

- **`anchor_mouse_spells`:** the spell branch `main.lua:4035-4056` is not in the
  fix diff (see §2); behavior identical to before the fix and shape-identical
  to 0.8.3 `2812-2824`. With `anchor_mouse` off and `custom_pos` set, a
  spell/action parent that misses the action/spellId probe falls to the gate,
  is classified, and now re-pins — exactly as 0.8.3 pinned every caller.
- **`anchor_mouse` on:** non-managed call → `main.lua:4078` early-returns
  (same as pre-fix, where the bare `return` always fired). Managed call →
  falls to `main.lua:4082-4089`, the mouse-anchor branch, byte-shape identical
  to 0.8.3 `2826-2833`. No change either way.
- **`custom_pos` nil:** non-managed call → `main.lua:4078` early-returns
  (pre-fix behavior kept). Managed call → falls to
  `main.lua:4100-4103`, the two-bar bottom-right branch, byte-shape identical
  to 0.8.3 `2844-2847` (including the `+ 9`). VERIFIED against both quoted
  blocks.

### e. Counters — still tally, never gate the pin (VERIFIED)

`main.lua:4065-4071` increment `TT.ev.anchorSkippedMenu` /
`anchorSkippedUnresolved` on every skip-classified call (kind `"menu"` /
`"unresolved"`; kind `"addon"` is deliberately uncounted per the doc at
`main.lua:3925-3927`). The pin path (`4091-4099`) reads no `TT.ev` state — the
counters are pure tallies. Empirically pinned by Pin B (§3): on a counted call
the re-pin still lands, and the counter advances by exactly 1.

### f. First hover / re-hover / reset — net three-path summary

- **First hover:** hook pins at `4095-4098` in the SetDefaultAnchor call
  (before content); render may also pin at `2009`. Same as 0.8.3 Path A.
- **Re-hover (the broken path, hop B2 of
  `current-tooltip-save-regression.md`):** now re-pins unconditionally in the
  hook, as 0.8.3 did. The residue-dependent skip is gone for the
  `custom_pos`-on case.
- **Reset:** unchanged by this fix. `custom_pos`-nil hovers fall to the
  client/two-bar park; turn-off paths (`_Disable`, `/tacotip default`,
  migration/sanitizer) are untouched (not in the diff).

---

## 2. Diff integrity — the fix is ADDITIVE ONLY over the pre-existing dirty hunks (VERIFIED)

`git status --short` (whole repo):

```
 M Tests/harness/tooltip_test.lua
 M main.lua
?? <untracked workshop dirs / screenshot only>
```

No `options.lua`, `gearscore.lua`, `.toc`, or `Locale/` change exists.

`git diff --numstat`:

```
290	0	Tests/harness/tooltip_test.lua
32	17	main.lua
```

`git diff main.lua` contains exactly **8 hunks**:

| hunk | site | class |
|---|---|---|
| `@@ -165,10 +165,13` / `@@ -190,14 +193,17` / `@@ -216,8 +222,10` | `applyTooltipMaxWidth` width-memo-on-success | pre-existing dirty |
| `@@ -1518,… / @@ -1527,… / @@ -1548,…` | `getPortraitSideRightEdge` clamp removal | pre-existing dirty |
| `@@ -2221,6 +2227,7` | `clearTooltipVisuals`: `state.portraitRightEdge = nil` | pre-existing dirty |
| `@@ -4062,7 +4069,15` | **THE FIX**: `-        return` → `if (TacoTipConfig.anchor_mouse or not TacoTipConfig.custom_pos) then return end` (+7 comment lines) | fix lane |

Arithmetic: fix hunk = −1/+9; 32−9 = **23 added, 17−1 = 16 removed** for the
pre-existing hunks — exactly the "23+/16- width/portrait-edge hunks only"
dirty state recorded by `current-tooltip-save-regression.md` §0 before the fix
landed. **Nothing else in `main.lua` changed; the width/portrait hunks are
intact.** `Tests/harness/tooltip_test.lua` is purely additive (+290/−0): the
width/portrait pins (H1–H3 block, pre-existing) plus the new `RE-HOVER ANCHOR`
block at `tooltip_test.lua:5105-5234`.

---

## 3. Independent validation — exact outputs (VERIFIED, run by this desk)

### 3.1 Suite matrix

```
bash Tests/harness/run_all.sh            -> TOTAL 71 invocations: 71 passed, 0 failed
LUA=lua5.4 bash Tests/harness/run_all.sh -> TOTAL 71 invocations: 71 passed, 0 failed
LUA=luajit bash Tests/harness/run_all.sh -> TOTAL 71 invocations: 71 passed, 0 failed
```

All three interpreters present on the machine (lua5.1 default, lua5.4, luajit).
Harness output names the tooltip pipeline green on **all five families**:

```
  ok    tooltip_test CLASSIC_ERA
  ok    tooltip_test TBC_ANNIV
  ok    tooltip_test TITANFORGE
  ok    tooltip_test FOREVER
  ok    tooltip_test RETAIL
```

(and likewise `batch8_pane_test` / `taint_test` ×5, `talent_check` ×3,
`gearscore_test` ×5 — full tail captured during the run.)

Per-family check totals on the fixed tree (from the revert-proof runs' sibling
invocations): CLASSIC_ERA/TBC_ANNIV/TITANFORGE `ALL 249 PASS` (legacy),
FOREVER/RETAIL `ALL 257 PASS` (pipeline).

### 3.2 Lint and package

```
luacheck .   -> Total: 0 warnings / 0 errors in 88 files
bash Tools/verify_release.sh --worktree -> verify_release: PASS
  (PASS single .toc / no workshop directories / no workshop documents /
   runtime files only)
```

### 3.3 THE REVERT PROOF — my own copy, per pin (VERIFIED)

Method (per the `hands-up.md` trap "a pin that passed while the fix was
reverted"): copied the tree to `/tmp/opencode/audit-revert` (no `.git`),
reverted **only** the fix hunk in `main.lua` — replaced the 7-line comment +
`if (TacoTipConfig.anchor_mouse or not TacoTipConfig.custom_pos) then return end`
block with the pre-fix bare `        return`, counters kept (exact-string
replacement, asserted exactly one occurrence). The new pins in
`tooltip_test.lua` were kept. Each pin resets its own mock state before running
(`resetRehoverResidue`, `tooltip_test.lua:5156-5166`), so neither pin can ride
the other's state. Ran `tooltip_test` per family under lua5.1. Result —
**both new pins go RED on all five families**, and nothing else fails:

```
=== tooltip_test 2 11509 CLASSIC_ERA ===
    FAIL re-hover with empty residue ends with one point on the drag handle points=1 relIsHandle=false point=BOTTOMRIGHT/BOTTOMRIGHT
    FAIL ...and the re-pin still happened on that counted call relIsHandle=false
CLASSIC_ERA  legacy    lines=7    2/249 FAILED
=== tooltip_test 5 20506 TBC_ANNIV ===
    FAIL re-hover with empty residue ends with one point on the drag handle points=1 relIsHandle=false point=BOTTOMRIGHT/BOTTOMRIGHT
    FAIL ...and the re-pin still happened on that counted call relIsHandle=false
TBC_ANNIV    legacy    lines=7    2/249 FAILED
=== tooltip_test 11 38002 TITANFORGE ===
    FAIL re-hover with empty residue ends with one point on the drag handle points=1 relIsHandle=false point=BOTTOMRIGHT/BOTTOMRIGHT
    FAIL ...and the re-pin still happened on that counted call relIsHandle=false
TITANFORGE   legacy    lines=7    2/249 FAILED
=== tooltip_test 1 16001 FOREVER pipeline ===
    FAIL re-hover with empty residue ends with one point on the drag handle points=1 relIsHandle=false point=BOTTOMRIGHT/BOTTOMRIGHT
    FAIL ...and the re-pin still happened on that counted call relIsHandle=false
FOREVER      pipeline  lines=6    2/257 FAILED
=== tooltip_test 1 120105 RETAIL pipeline ===
    FAIL re-hover with empty residue ends with one point on the drag handle points=1 relIsHandle=false point=BOTTOMRIGHT/BOTTOMRIGHT
    FAIL ...and the re-pin still happened on that counted call relIsHandle=false
RETAIL       pipeline  lines=6    2/257 FAILED
```

Reading of the failure modes: Pin A (`tooltip_test.lua:5202-5205`) fails with
the seeded client park `BOTTOMRIGHT/UIParent` still on the frame
(`points=1` — one point, but the WRONG one; had `ClearAllPoints` run and only
the SetPoint been skipped, it would have been `points=0`) and
`relIsHandle=false` — the re-pin never happened. Pin B
(`tooltip_test.lua:5216-5221`): the counter check still passes on reverted code
(counters pre-date the fix), but the paired "re-pin still happened" check goes
red — the two-check design catches exactly that. Exactly 2 failures per
family, none outside the new block — the revert isolates the two pins.

On the fixed tree the same invocation reads
`TBC_ANNIV legacy lines=7 ALL 249 PASS`. The copy was deleted after the run.

**Both pins can fail, and they fail for the right reason. The green suite on
the fixed tree is meaningful.**

---

## 4. Cross-client sanity (VERIFIED)

- **Hook registration unchanged by the fix.** The registration block
  `main.lua:4127-4156` — `if (type(_G.GameTooltip_SetDefaultAnchor) == "function")
  then hooksecurefunc("GameTooltip_SetDefaultAnchor", function(tooltip, parent)
  … return runUntainted(function() local ok, err =
  pcall(onGameTooltipSetDefaultAnchor, tooltip, parent) … end) end)
  TT.HookedDefaultAnchor = true` — appears in **no** diff hunk (§2); it is the
  committed 0.8.4 shape, differing from 0.8.3 `main.lua:2862-2864` (direct body
  hook) only by the `runUntainted`+`pcall` wrapper added earlier in 0.8.4. The
  fix touched only the body's skip logic.
- **The hook installs on all five families.** `GameTooltip_SetDefaultAnchor`
  exists on every supported client (classic override on
  classic_anniversary/era/titan; shared definition on forever/live —
  `anchor-client-truth.md` §(a), and the mirror), so the file-scope guard
  passes everywhere and `TT.HookedDefaultAnchor` is true. The harness proves
  the body runs on all five: `tooltip_test` green on
  **CLASSIC_ERA (11509), TBC_ANNIV (20506), TITANFORGE (38002), FOREVER (16001,
  pipeline), RETAIL (120105, pipeline)** — quoted in §3.1 — and `load_test`
  additionally covers the degraded shape ("ERA/RETAIL without
  GameTooltip_SetDefaultAnchor" ok).
- The operator's branch, classic_anniversary, is the TBC_ANNIV lane — green
  here and red-under-revert above, i.e. the pin exercises exactly the client
  family the operator plays.

---

## 5. Failure hunt — does the unconditional re-pin hurt any non-unit caller? (VERIFIED, no regression found)

`GameTooltip_SetDefaultAnchor` is called by far more than unit frames on
classic_anniversary (mirror grep, `origin/classic_anniversary`, non-definition
call sites include): `Blizzard_ActionBar/Shared/ActionButton.lua:1104`,
`SpellFlyout.lua:71`, `StanceBar.lua:132`, `PetActionBar.lua:319`,
`PossessActionBar.lua:96`, `Blizzard_CharacterFrame/Wrath/PaperDollFrame.lua:2249`
(item buttons), `Blizzard_GameTooltip/Classic/GameTooltip.lua:470`,
`GameTooltipTemplate.lua:13` (`OnTooltipSetDefaultAnchor`), Minimap/Auction/
PVP/Honor frames, etc. So yes — the hook fires for item, spell and various
panel surfaces, not only units.

Why the unconditional re-pin is still correct on those surfaces:

1. **0.8.3 shipped exactly this.** `/home/sam/TacoTip/main.lua:2835-2842` pinned
   EVERY `SetDefaultAnchor` caller to the handle when `custom_pos` was set —
   item hovers, panel buttons, all of it — and the operator used it (bench
   `prior-tooltip-save-mechanism.md` §6: "the hook applies the former
   unconditionally whenever Blizzard asks for a default anchor"). The fixed
   code restores that contract; the pin lands in the same call stack, before
   the tooltip is presented.
2. **Spell/action parents keep their designed early branch** before the
   fall-through: `main.lua:4035-4056` re-owns them `ANCHOR_LEFT/RIGHT` and
   returns — same order as 0.8.3 `2812-2824`. Only when `anchor_mouse_spells`
   is OFF (or the probe misses) can a spell surface reach the pin — and that
   was also true in 0.8.3, which pinned it.
3. **The secure-surface concern is carried by the taint wrapper, not the
   skip.** The gate's own comment (`main.lua:4058-4061`) frames the passthrough
   as taint hygiene, but the committed 0.8.4 containment for that is
   `runUntainted` around the whole body (`main.lua:4142-4149`, rationale
   `5377-5387`-class comments), which the fix does not touch. The fix does not
   add a SetPoint site; it widens the reach of the existing one to the 0.8.3
   extent inside the existing wrapper. The game-menu Logout/Quit callback does
   not route through `SetDefaultAnchor` (mirror), and the taint-test pins stay
   green on all five families (`taint_test` ×5, §3.1).
4. **ShoppingTooltip1/2 and ItemRefTooltip are separate frames** positioned by
   `SetOwner` relative to GameTooltip — they never call
   `GameTooltip_SetDefaultAnchor` themselves (absent from the call-site grep),
   so the hook cannot drag them; they follow GameTooltip, which is intended.
5. **No new corrupt-shape exposure.** The fall-through checks only
   `custom_pos` truthiness; that was already true for managed calls pre-fix
   and for ALL calls in 0.8.3. The `ADDON_LOADED` sanitizer
   (`main.lua:5349-5353`) nils corrupt shapes at load, same as 0.8.3.

One residual behavior difference vs the PRE-fix 0.8.4 tree, worth stating
plainly (not a defect): with `custom_pos` set, menu-classified and
unresolved-classified calls are no longer passed through untouched — they
re-pin, as in 0.8.3. The counters that used to mean "pin skipped" now mean
"gate said menu/unresolved"; the diag labels at `main.lua:4824-4825`
("anchor passthrough") are therefore slightly generous for the `custom_pos`-on
case. Cosmetic; the operator's `/tacotip diag` interpretation should read
those tallies as classification counts, not skip counts, from now on.

---

## 6. Verdict

**AUDIT PASS.** All six audit tasks verified against the live tree, the client
mirror and my own runs:

1. Three-path trace: the hook re-pins unconditionally on every
   `SetDefaultAnchor` call when `custom_pos` is set and `anchor_mouse` is off
   (0.8.3 contract restored); no remaining position window; ClearAllPoints
   precedes SetPoint; mouse/spell/nil modes byte-shape-unchanged; counters
   tally without gating; diff is additive-only over the intact 23+/16-
   width/portrait hunks with no collateral file changes.
2. Independent validation: 71/71 ×3 interpreters, luacheck 0/0 in 88 files,
   `verify_release --worktree` PASS.
3. Revert proof (my own copy, per pin, mock state reset per pin): both new
   pins RED on all five families, exactly 2 failures each, correct failure
   semantics; copy deleted.
4. Cross-client: registration untouched; all five families green and named.
5. Failure hunt: non-unit callers handled exactly as 0.8.3 handled them; taint
   containment is the wrapper, unchanged.

**Pinned in the harness, not observed in game.** Per `hands-up.md`, the
operator's next hover on classic_anniversary — save a position, leave, re-hover
the same unit (and an item button) — is the acceptance. No in-game observation
exists from this lane, and none is claimed.

*End of audit. No code was modified in the repo; the only writes were this
finding, the desk journal, and the signal.*
