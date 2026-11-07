# 0.9.5 — Portrait stability + locale rendering — Journal

## 2026-11-06 — Desk opened: 0.9.5 (Forever/Retail portrait + locale)

- **Purpose:** stabilize the 3D portrait on Retail/WoW Forever unit-frame hover
  (player/target/pet/party/raid), fix non-Latin locale glyph squares, and settle
  the "Right click for Frame Settings" instruction line on unit tooltips.
- **Scope:** TacoTip root add-on only. `TacoTip_Extras` out of scope. Classic
  families must not change behavior. `custom_pos`, `custom_anchor`, the dot,
  `syncTooltipMoverPosition` and the `GameTooltip_SetDefaultAnchor` hook are
  untouchable. No revert or rework of the 0.9.2–0.9.4 fixes; this is additive.
- **Operator evidence:** long-standing portrait blink/jitter on Retail + Forever
  unit frames (NOT classic); quick off/on mouseovers jitter; "some languages not
  supports. I see squares sometime"; unit-frame tooltip shows the Frame Settings
  instruction line; rare "tooltip flashes at the old position" and "tooltip
  sticks to the cursor when a moving player runs away" reports.
- **Client truth already read:** `origin/forever`
  `Blizzard_UnitFrame/Mainline/UnitFrame.lua:388-407` (`UnitFrame_UpdateTooltip`
  re-drives `SetUnit` every `TOOLTIP_UPDATE_TIME` = 0.2s and appends
  `UNIT_POPUP_RIGHT_CLICK` after the post-call);
  `Blizzard_SharedXMLGame/Tooltip/TooltipDataHandler.lua:272-300`
  (`ClearLines` -> ProcessLines -> post-calls -> `Show`, i.e. the addon renders
  against a not-yet-shown frame);
  `Blizzard_Fonts_Shared/**` (per-alphabet fonts: ruRU `FRIZQT___CYR.TTF`,
  koKR `2002.TTF`, zhCN `ARKai_T/C.ttf`, zhTW `blei00d.TTF`).
- **Next step:** implement locale-safe font resolution, modern-only portrait
  lifecycle fixes, instruction-line suppression; pin each; run gates.

## 2026-11-06 — Implementation: portrait stability + locale rendering (0.9.5 build)

- **Worked on:** (1) Modern portrait lifecycle: `noteOwnerUnitGUID` records the
  owner frame's unit GUID before resolution; `isUnitFramePeriodicUpdate` accepts
  it as an identity proof and waives the missing `owner.UpdateTooltip` while the
  tooltip is shown (OnLeave nils it before FadeOut). Portrait side decision
  extracted to `anchorTooltipPortrait`; `onTooltipShow` calls it with a force
  flag so the first presented frame already has the correct edge (Classic
  untouched; OnShow branch gated `isForever or isRetail`). Zoom/alpha/Show are
  memoized. (2) Locale: `TT:GetLocaleFontPath` (client alphabet first, then a
  non-roman override), `GetResolvedTooltipFont` treats the shipped roman default
  as "client default", `ttFilterFontList` keeps only script-bearing built-ins
  per non-roman client, added CYR/ARKai/Blei entries, removed the duplicate
  uppercase BLEI, SetFont failure is no longer cached as success, three orphan
  enUS array strings removed. (3) `onTooltipShow` blanks Blizzard's
  `UNIT_POPUP_RIGHT_CLICK` hint on modern unit tooltips (one spacer row remains;
  no line-removal API).
- **Deliberately not shipped:** the `UPDATE_MOUSEOVER_UNIT` stale-tooltip
  safety net prototyped during this lane. The two `pryll_` reports (position
  flash, tooltip sticking to the cursor) trace to the client's tooltip
  lifecycle; a second symptom gets a line in the report, not an edit. The
  prototype was reverted before the final tree.
- **Tests:** Forever harness P15 (+red/green proof on HEAD: 4 red), locale-font
  matrix in `tooltip_test` (red on HEAD options: 2 red), `font_test` is now a
  renderability pin on all six locales (red on HEAD textures: every non-roman
  locale). `run_all.sh` **72/72 on lua5.1, lua5.4 and luajit**; `luacheck .`
  **0/0 in 88 files**; both `verify_release* --worktree` **PASS**. Forever pins
  **85/85**. Version bumped to **0.9.5** (TOC, fallbacks, README, AGENTS, harness
  pins).
- **Tree note:** removed the accidentally tracked
  `mnemon-mirror/runtime/MEMORY.md` (agent memory mirror, not addon runtime) and
  added `mnemon-mirror/` to `.gitignore`; the verifier had been failing on it.
- **Current state:** 0.9.5 build ready for the operator's in-game pass. Portrait
  behavior on Retail/Forever unit frames must be confirmed live; the locale fix
  needs a Russian/Chinese/Korean client confirmation; the Frame Settings row
  should be re-checked (text gone, one blank row expected).
- **Next step:** operator in-game verification, then fix whatever the live
  client contradicts (portrait is the priority). Known residual: font dropdown
  label mismatch on roman-client + non-roman override (cosmetic).

## 2026-11-06 — [signal:checkpoint] 0.9.5 build ready for in-game verification
- Gates green; portrait/locale/hint fixes pinned; operator pass is the next rung.

## 2026-11-06 — Pre-test correctness review (self + two independent read-only audits)

- **Fixed during review:** (1) the Frame Settings blank was only applied in
  `OnShow`, but `Show()` is a no-op on an already-shown frame while
  `UnitFrame_UpdateTooltip` re-adds the line every 0.2 s — added a guarded
  secure post-hook on `UnitFrame_UpdateTooltip` and a pin for the refresh path.
  (2) `onTooltipShow` anchored `TacoTipPortrait3D` even when the player had
  toggled 3D off and the visible portrait was the 2D texture; it now anchors
  the region the config actually renders. (3) NPC portrait path verified and
  pinned for both 3D and 2D (operator said "nvm" after asking; pins kept as
  regression coverage).
- **New pins:** Forever 90/90 (14 in P15); `tooltip_test` +5 (4 locale-font,
  1 cross-client gate: Classic tears down, modern skips); `locale_test` +
  structural parity (keyed set + placeholders across all 11 tables, red-proven
  by deleting a ruRU key and by changing a `%s` to `%d`). Full matrix
  **72/72 × lua5.1/5.4/luajit**, `luacheck` 0/0 in 88 files, both verifiers
  PASS.
- **Review verdict:** no blocker found beyond the two fixes above. Remaining
  proposals (deliberately not changed without operator approval): include the
  portrait width in the right-edge side test (would flip the portrait left at
  the stock bottom-right anchor — a visible change), append a locale face to
  the font dropdown for roman-client + non-roman override (needs a label),
  and add a line-replay cache only if profiling shows a hitch.
- **Next step:** operator in-game pass.

## 2026-11-06 — Independent audit round integrated

- **Portrait audit (fresh read-only reviewer):** confirmed the owner-GUID
  identity proof and the Classic gate shape; found (1) the forced OnShow anchor
  could LATCH a zero `GetRight()` for the whole hover — now
  `portraitAnchored = shown and tooltipRight > 0`, so a zero measurement is
  re-measured on the next rendered tick; (2) the owner-GUID proof was not
  actually pinned (deleting it stayed green) — added the sole-proof and
  changed-owner pins; (3) the OnShow hint blank was an engine-impossible path
  and its pin was unfaithful — removed the OnShow call/pin, kept the secure
  `UnitFrame_UpdateTooltip` post-hook with its faithful pin; (4) `SetUnit`'s
  boolean return was read as the pcall status — fixed (`okCall and setResult ~=
  false`) and pinned; (5) the right-edge threshold ignoring the portrait width
  is pre-existing and remains a proposal (default anchor flip would be a
  visible change).
- **Locale audit (fresh read-only reviewer):** found the font filter ran at
  file scope on `GetLocale()` before SavedVariables, so a Titanforge/override
  client saw roman faces; moved filtering into `GetTooltipFontChoices` at
  runtime on `TT:GetDisplayLocale` (client alphabet first, then the override).
  Accented-Latin clients now keep their client face under ruRU/zhTW overrides
  (`FRIZQT___CYR` has no é/ï/ö; `bLEI00D` no Latin); the ruRU allow-list now
  keeps the LSM-verified ARIALN/2002/2002B/K_Pagetext; `FRIZQT_.TTF` and
  Latin-less `K_Damage.TTF` are removed; docs claims scoped to the built-in
  list (SharedMedia is unclassified). `font_test` and `locale_test` had no
  `os.exit`, so failures were non-gating — both now exit 1; the in-game font
  test uses the effective display locale. Owner-GUID proof is gated to modern
  (Classic contract now true).
- **State:** latest fixes re-run: **72/72 on lua5.1, lua5.4 and luajit**;
  Forever **92/92**; `luacheck` 0/0 in 88 files; both verifiers PASS. Red
  proofs: HEAD main 86/92 (6 red), HEAD textures font_test exits 1, mutated
  ruRU locale_test exits 1. `tooltip_test` FOREVER/RETAIL 200 checks, Classic
  194.
- **Next step:** operator in-game pass; the edge-threshold flip remains the one
  proposed visible improvement awaiting approval.

## 2026-11-06 — Final audit pass: unverified faces removed, docs precision

- **M1 closed:** the six `Fonts\ZY*.TTF` entries were referenced by no
  `Blizzard_Fonts_Shared` XML on any of the five branches (forever/live/
  classic_era/classic_anniversary/classic_titan) and are absent from the bundled
  LibSharedMedia coverage table — removed from the built-in list and the
  zhCN/zhTW allow-lists. `2002B.TTF` is verified (`GameFontStyles.xml`
  UNIT_NAME_FONT_KOREAN) and kept. The only remaining broken-built-in-face
  route is gone.
- **Docs/comments:** accented-Latin wording now names both ruRU and zhTW;
  `bLEI00D` is described as lacking accented Latin (not all Latin); the
  "alphabet of the displayed language" claim is reworded to client-first with
  override compatibility; the now-false dropdown-label caveat is removed; a
  non-roman client + different-script override known issue is recorded.
- **Test fix:** `tooltip_test`'s font-change probe needed a second face; on a
  script-filtered locale it now temporarily appends the client-verified
  `ARKai_C` to the filtered list, then restores the filter. This keeps the
  latch case tested instead of failing on a one-entry list.
- **Gates (final):** run_all **72/72 on lua5.1, lua5.4 and luajit**; Forever
  **92/92**; tooltip_test FOREVER/RETAIL **200**, Classic **194**; font_test
  **7/7/5/3/1/1**; luacheck **0/0 in 88 files**; both verifiers PASS.
- **Residual (low):** unbounded SetFont retry only reachable via a stale
  SharedMedia path now; non-roman client + different-script override labels
  (documented); Titanforge builds reporting a non-zhCN `GetLocale` use that
  face while the labels are zhCN (rare, unverified); the portrait-width
  right-edge flip remains the one proposed visible improvement.
