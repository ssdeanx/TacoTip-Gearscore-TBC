```
   _____              _____ _____
  |_   _|            |_   _|__  / __|
    | | |__   __ _  __  | |  / /|  _\
    | | '_ \ / _` |/ _` | | / / | |  \
    | | | | | (_| | (_| | |/ /__| |_) |
    |_|_| |_|\__, |\__,_|_/_____|____/
             __/ |
            |___/
```

```yaml
name: TacoTip
version: 0.9.8
author: AcidBomb
maintainer: AcidBomb (Pilsung)
license: MIT
curseforge_id: 1555962
project_url: https://www.curseforge.com/wow/addons/tacotip-gearscore
clients: [Classic Era / SoD, TBC Anniversary, WotLK Titanforge, WoW Forever, Retail]
interfaces: ["11509", "20506", "38002", "16001", "120105"]
tags: [tooltip, gearscore, gear-score, 3d-portrait, class-colors, talents, pawn, inspect, enhancement, cross-engine]
requires: [LibStub, CallbackHandler-1.0, LibDetours-1.0, Pawn, LibSharedMedia-3.0, SharedMedia]
status: pending in-game verification (2026-11-07)
updated: 2026-11-07
```

**TacoTip** is the premier, all-in-one tooltip enhancement for World of Warcraft. Built with a unified cross-engine architecture, a single installation runs seamlessly across **every** World of Warcraft client family — from Classic Era and Season of Discovery to The Burning Crusade Anniversary, WotLK Titanforge, WoW Forever, and Retail Live:

- **<span style="color:#fffe23"><span style="text-decoration:underline">Discord</span></span>** <https://discord.gg/nnbN4Naad>
- **<span style="color:#59f0dc"><span style="text-decoration:underline">CurseForge</span></span>**
— <https://www.curseforge.com/wow/addons/tacotip-gearscore> (this add-on)

- **<span style="color:#e67e23"><span style="text-decoration:underline">Companion App</span></span>**
— [TacoTip Extras](https://www.curseforge.com/wow/addons/tacotip-extras/preview) ![TacoTip Extras](https://media.forgecdn.net/attachments/2065/485/2-png.png) *(Guild rank browser, player gear leaderboard & historical stat tracking)*

| Client Family | Supported Interface | Client Status |
| :--- | :--- | :--- |
| **<span style="color:#f39c12">Classic Era / Season of Discovery (SoD)</span>** | `11509` | <span style="color:#2ecc71">**Active**</span> |
| **<span style="color:#2ecc71">The Burning Crusade Classic Anniversary</span>** | `20506` | <span style="color:#2ecc71">**Active**</span> |
| **<span style="color:#3498db">WotLK Titanforge</span>** | `38002` | <span style="color:#2ecc71">**Active**</span> |
| **<span style="color:#9b59b6">WoW Forever</span>** | `16001` | <span style="color:#2ecc71">**Active**</span> |
| **<span style="color:#e74c3c">Retail / Live (The War Within & Midnight)</span>** | `120105` | <span style="color:#2ecc71">**Active**</span> |

> **<span style="color:#e67e23">This release replaces the previous Classic-only TacoTip.</span>** It is the same
> addon, continued — your existing configuration carries over, and the GearScore
> numbers you are used to are unchanged on the Classic clients. What is new is
> that the identical build now also works on WoW Forever and Retail.
---
> 🎉 **<span style="color:#fffc11">200,000+ Downloads Milestone:</span>** A heartfelt thank you to the entire community! We just surpassed ****200,000 downloads**** and are growing faster than ever. Your continuous feedback, testing, and support have made all of this rapid progress possible — thank you for making TacoTip your go-to tooltip addon!

---

## <span style="color:#e67e23">What's New in v0.9.8</span>

- 🧭 **<span style="color:#59f0dc">Zone Line on WoW Forever Player Frames:</span>** Hovering a player, target, party or raid frame now adds a `Zone:` row directly under the `Target:` row (or under the level line on your own frame). The zone comes from the client's own map data — `C_Map.GetBestMapForUnit` to find the unit's map, then `C_Map.GetMapInfo` for its localized name — and the label is the client's localized `ZONE` string, so no translation is invented. The row covers players only and appears only when the client can actually place the unit; a target outside your group, or any unit the client cannot locate, simply gets no row instead of a guessed zone. Forever only: Classic Era, TBC Anniversary, WotLK Titanforge and Retail are byte-identical.
- 🛡️ **<span style="color:#59f0dc">Loot-Window Tooltips Left Native (WoW Forever):</span>** The item tooltip in the loot bag is built by `GameTooltip:SetLootItem` from secret tooltip data, and the loot window rebuilds it every frame. Modifying it from addon code is what drops the client's own armour-type row (`Cloth` / `Mail` / `Plate`), which was reported in-game. TacoTip now leaves that one tooltip exactly as the client builds it — no tooltip-data reads, no Item Level or GearScore rows, no font or backdrop pass — so the client renders its own armour-type row. Normal item tooltips (bags, character frame, chat links) keep the Item Level and GearScore rows unchanged, and no other client family is touched. This is the trade-off: the loot bag shows the client's tooltip, not TacoTip's extra rows.
- 🧪 **<span style="color:#59f0dc">Pins:</span>** `forever_tooltip_test` is now **134/134**. Zone: player/party/raid frames show the row; a group-member target frame resolves through its own party/raid token; a resolved `mouseover` token still asks the owner frame's unit; nameplate, focus and NPC hovers do not; no map answer means no row; the row sits directly under Target; the label follows the client's `ZONE` string; and per-unit map answers are read after load. Loot: the loot tooltip keeps its exact line count, gains no TacoTip row, and a normal item tooltip still gets the rows; OnShow performs zero tooltip-data reads there. Talents: the inspected readout renders even when `GetNumSpecGroups(true)` answers nothing, and `/tt diag` reports the hovered player's own talent data. The shared `tooltip_test` gains a cross-client pin that the zone row is Forever-only (it turns red on Classic Era if the `isForever` gate is removed) and that it does render on Forever.
- 🏷️ **<span style="color:#59f0dc">Version:</span>** **0.9.8** (in-game verification pending). TOC, Lua fallbacks, README, CHANGELOG, AGENTS and the harness version pins move together.

---

## <span style="color:#e67e23">What's New in v0.9.7</span>

- 🧠 **<span style="color:#59f0dc">Talents Are Back on WoW Forever:</span>** Forever is the Camelot client, and its talent system is not Retail's: one class-level specialization, three talent trees (trait node groups) and up to two spec groups (Primary/Secondary). The tooltip now reads the client's own data — tree names and icons from `C_Traits.GetGroupDisplayInfoByTreeID`, per-tree points from `C_Traits.GetGroupCurrencyInfo` — and renders the TBC shape: the tree with the most points plus `[p1/p2/p3]`, active group first and the inactive group dimmed. A character with no points yet shows the `[0/0/0]` template instead of disappearing.
- 👥 **<span style="color:#59f0dc">Own vs Inspected:</span>** On your own character both spec groups are read (`GetNumSpecGroups`, `C_SpecializationInfo.GetCombatConfigIDForSpecGroup`), so a dual-spec character gets two lines. An inspected player's active group comes from the documented inspect trait config (`Constants.TraitConsts.INSPECT_TRAIT_CONFIG_ID`, `-1`); the inactive group is attempted through `C_SpecializationInfo.GetTalentInfo` and appears only if the client answers — no fabricated line.
- 🧱 **<span style="color:#59f0dc">Nothing Else Moved:</span>** The old Retail/Classic talent block keeps its `show_talents and not isForever` gate byte-identical; the Forever readout is a separate `isForever` branch. No Classic or Retail behavior changed, and the Classic `spec_table`/`talents_table` data is not used for Forever.
- 🧪 **<span style="color:#59f0dc">Pins:</span>** `forever_tooltip_test` is now **108/108**, covering one line without dual spec, two lines with it, `[0/0/0]`, a missing `C_Traits` namespace (no line, no error), late inspect data, wrong-GUID safety, and a silent inactive-group query (one line only).
- 🏷️ **<span style="color:#59f0dc">Version:</span>** **0.9.7** (in-game verified 2026-11-07). TOC, Lua fallbacks, README, CHANGELOG, AGENTS and the harness version pins move together.

---

## <span style="color:#e67e23">What's New in v0.9.6</span>

- 🖱️ **<span style="color:#59f0dc">One Dropdown, Not Two (WoW Forever / Retail):</span>** The media picker is a custom scrollable list drawn on top of Blizzard's dropdown frame. On the modern pair the template's arrow is a `DropDownToggleButton` whose activation is `DropDownMenuButtonMixin:OnMouseDown`; the Classic family's arrow uses the XML `OnClick`. The old code replaced only `OnClick`, so on Forever/Retail one click fired the stock menu on mouse-down **and** TacoTip's picker on click. The picker now replaces whichever handler the client installed and clears the other, so one click opens exactly one list. The Classic path is unchanged in shape (it already replaced `OnClick`), and no dropdown is removed, restyled or re-anchored.
- ⚡ **<span style="color:#59f0dc">Power Bars on Forever / Live:</span>** On the modern secret clients, `UnitPowerMax` and `UnitPower` are **secret** while a unit's power is restricted (`SecretWhenUnitPowerMaxRestricted` / `SecretWhenUnitPowerRestricted`). The old show gate compared the max with `> 0`, and a secret value cannot be compared, so the bar never appeared. The gate now shows the bar and passes the secret values untouched to `SetMinMaxValues`/`SetValue`; the client documents those as accepting secret bar values (`AllowedWhenTainted` plus `SecretAspect.BarValue`). Non-secret clients keep the original `max > 0` behavior, and Classic Era, TBC and Titanforge are unchanged.
- 🏆 **<span style="color:#59f0dc">Achievement Points Are Retail-Only:</span>** The achievement-points toggle is now enabled only on Retail. It is disabled on Classic Era, TBC Anniversary, WotLK Titanforge and WoW Forever, and the unit render is gated with `isRetail` so a saved true value cannot add an achievement row on a client that is not supposed to show it. Retail behavior is unchanged; the saved-variable key is untouched.
- 🔤 **<span style="color:#59f0dc">Font Rows Are Fonts, Not Green Blocks:</span>** Font choices are file paths (`Fonts\FRIZQT__.TTF`), and the picker treated any value containing `\` or `/` as a texture, passing the font file to `Texture:SetTexture`. The client draws an unloadable texture as a solid green block. Texture preview is now opt-in per dropdown (status bar, border, background only); the font list renders each row in its own face, with a refused path falling back to the default row font. SharedMedia fonts preview too, and the row buttons are reset between pickers so no preview leaks.
- 🧪 **<span style="color:#59f0dc">Pins:</span>** Twelve new checks in `options_test` cover the media picker (one activation handler, no stock menu, one custom picker, font rows rendered as text in their own face, texture previews preserved). Four new `tooltip_test` checks cover the power bar (a secret `UnitPowerMax` shows the bar and is passed through, a non-secret zero max still hides it) and the achievement gate (present on Retail, absent on the other four). The `settings_test` achievement toggle now expects Retail only. Red proof: pre-fix media picker 6/79 Forever and 4/79 Classic; pre-fix power gate 3/204 Forever (including `attempt to compare number with table`); pre-fix achievement row 1/204 on Forever; an always-show mutant fails the zero-max pin; the old achievement gate fails 1/65 on Forever and Titanforge while Retail stays green. Fixed: 79/79 options, 204/198/204 tooltip, 65/65 settings.
- 🏷️ **<span style="color:#59f0dc">Version:</span>** **0.9.6** (test build; in-game verification pending). TOC, Lua fallbacks, README, CHANGELOG, AGENTS and the harness version pins move together.

---

## <span style="color:#e67e23">What's New in v0.9.5</span>

- 🖼️ **<span style="color:#59f0dc">Portrait Stability on Unit Frames (Retail / WoW Forever):</span>** The 3D portrait no longer blinks or jumps while the mouse sits on the player, target, pet, party or raid frame. The client re-drives `GameTooltip:SetUnit` every 0.2 s (`TOOLTIP_UPDATE_TIME`); that re-drive clears the lines first, and `UnitFrame_OnLeave` nils the frame's `UpdateTooltip` before its fade-out starts. The clear hook now proves "same unit frame, same unit" from the owner's own unit GUID (recorded before the unit token is resolved), so it cannot tear the portrait down on a tick whose resolution has not run yet, and the OnLeave window no longer resets the portrait while it is on screen. The portrait's side is recomputed from the laid-out tooltip in `OnShow` — before the frame is presented — instead of one tick late, so the edge flip is gone when the tooltip is anchored at the screen edge. NPCs render on both the 3D model and the 2D fallback. Classic clients keep the previous behavior; every new branch is gated to the modern pair.
- 🌍 **<span style="color:#59f0dc">Non-Latin Locales Render Their Own Glyphs:</span>** The client ships one font file per alphabet (`FRIZQT__.TTF` roman, `FRIZQT___CYR.TTF` Cyrillic, `2002.TTF` Korean, `ARKai_T.ttf` Simplified Chinese, `blei00d.TTF` Traditional Chinese). TacoTip's shipped default was the roman face, and it re-fonts every tooltip line — including Blizzard's own name/race/level/guild rows — so Russian, Korean and Chinese text rendered as missing-glyph boxes ("squares"). The resolver treats the historical default as "client default": it prefers the client's alphabet, follows a non-roman addon-language override only where that face can carry the client's Latin, and keeps the client face on an accented-Latin client under a Russian or Traditional-Chinese override, because those faces lack accented Latin.
- 🔤 **<span style="color:#59f0dc">Font Picker No Longer Offers Broken Faces:</span>** The **built-in** list is filtered at runtime on the effective display language — client alphabet first, then a non-roman addon-language override — so a roman-only face is no longer offered where it would box every line. The Cyrillic, ARKai and Blei faces are listed; an accented-Latin client keeps its own face under a Russian or Traditional-Chinese override because those faces do not carry é/ï/ö. SharedMedia fonts are the player's own additions and are not classified. A failed `SetFont` is no longer cached as success.
- 🖱️ **<span style="color:#59f0dc">"Right click for Frame Settings" Row Removed on Modern Unit Tooltips:</span>** That row is Blizzard's own `UNIT_POPUP_RIGHT_CLICK` instruction line, appended by `UnitFrame_UpdateTooltip` after TacoTip's unit post-call and immediately before `Show()`. It is blanked by a secure post-hook on `UnitFrame_UpdateTooltip`: that hook runs after the line is added, while `OnShow` fires before it exists and the repeated `Show()` is a no-op on an already-shown frame. The client adds a blank spacer line with it and the tooltip API has no line-removal call, so one empty row remains at the bottom.
- 🧪 **<span style="color:#59f0dc">Pins:</span>** Sixteen new Forever pins (five 0.2 s re-drives do not hide or destroy the model; the first re-drive after OnLeave does not hide it; the owner GUID is the sole proof when the render could not resolve a unit, and a changed owner unit still hides; a non-throwing `SetUnit(false)` is not cached; a proven different unit still tears it down; NPC portraits on the 3D and 2D paths; OnShow re-anchors once and picks the left edge at the right screen edge; the instruction row is blanked after the 0.2 s refresh) plus eight locale-font checks (default faces, a non-roman client beating a different-script override, the runtime picker, and accented-Latin clients keeping their face under ruRU/zhTW overrides), a cross-client portrait-gate pin (Classic still tears down, modern skips), a locale structural-parity pin (keys + placeholders across all 11 tables), and a renderability pin on every built-in font list. Each fix pin was shown red on the pre-change code. Forever pins: **92/92**.
- 🧷 **<span style="color:#e67e23">Known issue (identified, not edited):</span>** the rare "tooltip flashes for a moment at its previous position" and "tooltip stays on the cursor after a moving player runs away" reports both come from the client's tooltip lifecycle (`GameTooltip_SetDefaultAnchor` / `FadeOut` ordering and the world-cursor hide path), not from TacoTip's renderer. They are left for a separate investigation so this build does not add an unrequested behavior.
- 🏷️ **<span style="color:#59f0dc">Version:</span>** **0.9.5** (test build; in-game verification pending). TOC, Lua fallbacks, README, CHANGELOG, AGENTS and the harness version pins move together.

---

## <span style="color:#e67e23">What's New in v0.9.4</span>

- 🧨 **<span style="color:#59f0dc">Tooltip Taint Root Cause (WoW Forever):</span>** The Forever-only `GameTooltip.AddLine`/`AddDoubleLine` override is **removed**. Overriding a method on `GameTooltip` taints the frame; Blizzard's secure tooltip pipeline (`SetUnitAuraByAuraInstanceID` → `TooltipDataHandler:AddLineDataText`) then runs tainted and cannot test secret fields (`wrapText`, `leftColor`, `leftText`). That is the `attempt to perform boolean test on field 'wrapText'` error on buffs, and it is also why the player/pet unit tooltips stayed raw. The text guard was only a symptom patch; the override itself was the taint source.
- 🎯 **<span style="color:#59f0dc">FojjiCore Row Still Blocked, at the Source:</span>** With the override gone, the row is switched off through FojjiCore's own published option — `FojjiCoreNS.Tooltips.Set("bisGearScore", false)` — applied at load and again when `FojjiCore`/`FojjiCore_BiS` finishes loading. Nothing but FojjiCore is touched, and no other addon's tooltip lines are filtered.
- 🖱️ **<span style="color:#59f0dc">Mover No Longer Steals Unit-Frame Tooltips:</span>** `ShowExample` now returns while the tooltip's owner is a unit frame (`owner.unit`), so the player/pet/target frames keep their live tooltip and the client's 0.2 s re-drive. The cached player example is only drawn when the tooltip is hidden or the mover owns it; `custom_pos` and the saved position are untouched.
- 🧮 **<span style="color:#59f0dc">Self GearScore / iLvl / Pawn Fixed:</span>** The player has no inspect-cache record, so `CI:GetUnitData("player")` is nil. The first render registered the item-load callbacks and `TacoTip_GSCallback` then cleared the retry gate, so the re-render skipped `GetScore` entirely and the player tooltip stayed header-only. Self now always takes the live path; Pawn gets its own live memo (cleared on `PLAYER_EQUIPMENT_CHANGED`), and the external Pawn call is `pcall`-isolated so a Pawn throw cannot erase the GearScore/iLvl lines.
- ⚔️ **<span style="color:#59f0dc">Hunter 1H Finally Counts:</span>** The max-level hunter melee weight (×0.3164) is now applied only while a **ranged weapon is equipped**. A level-10 hunter whose green 1H raw-scores 2 but had no ranged weapon saw 2 × 0.3164 = 0.63 → floored to 0; the melee weapon now counts at full value. A positive total that still floors to 0 is clamped to 1 instead of hiding the line.
- 🧪 **<span style="color:#59f0dc">No Method Override Remains:</span>** The text predicate and row block are gone with the override. Pins assert `GameTooltip.AddLine`/`AddDoubleLine` are still the original functions, no `_tacoTipForeignScoreBlock` marker exists, and the FojjiCore option is the only row path.
- 🩺 **<span style="color:#59f0dc">Diagnostics Hardening:</span>** `/tt diag` no longer calls the protected `CheckInteractDistance` directly on Forever/Retail — that raised `ADDON_ACTION_BLOCKED` from the slash-command path. It reports `n/a (protected)` and prints `GearScore option` plus a `live self score` row, so a missing self line can be attributed to the option, the score, or the render.
- 🧷 **<span style="color:#e67e23">Known issues (deferred to 0.9.5):</span>** The 3D portrait can blink on unit-frame hover (portrait side-cache lifecycle, not the mover text fix). The `Right click for Frame Settings` row on player/target/pet/party hover is still under investigation. Both are separate from this release's fixes.
- 🏷️ **<span style="color:#59f0dc">Version:</span>** **0.9.4** (release build). TOC, Lua fallbacks, README, CHANGELOG, AGENTS and the harness version pins move together.

---

## <span style="color:#e67e23">What's New in v0.9.3</span>

- 🎯 **<span style="color:#59f0dc">Forever Player Tooltip Ownership:</span>** On Forever, every row past the name/guild/level header is dropped for **player** tooltips only, so a stale foreign score row or a previous render's row cannot be re-emitted through the write-back. Creature/NPC rows (titles, quest markers, trainer/repair tags) are preserved.
- 🧪 **<span style="color:#59f0dc">Inspect-Queue Diagnostics:</span>** `/tt diag` adds queue-overflow and queue-drain drop counters. Observability only — no gate, throttle or timing change.
- 🏷️ **<span style="color:#59f0dc">Version Bump:</span>** TOC and Lua fallbacks move to 0.9.3.

---

## <span style="color:#e67e23">What's New in v0.9.2</span>

- 🎯 **<span style="color:#59f0dc">WoW Forever Tooltip Parity (Talents Off):</span>** The Forever unit tooltip now matches the Classic reference — name/class color, level line, Target line, guild behavior, GearScore, iLvl, Pawn, portrait, borders — with the sole exception of Talents, which never render on Forever (no Talents line, spec text, or spec icon). The stale extra score row is gone, Pawn persists after item data when the score is positive, empty snapshots are never cached as fresh, and the Tooltip Style dropdowns apply to the open tooltip immediately. No other client family changes.
- 🧪 **<span style="color:#59f0dc">New Forever Acceptance Pins:</span>** A dedicated Forever harness file (71 pins: talents absent, Target, owned iLvl, all four styles, stale-row removal, Pawn persistence, empty-to-full recovery, spec index, guildless, NPC, own-tooltip, realm/inline/portrait/separator variants, render purity) proven red on the old code and green on the new, on all three interpreters. Pinned in the harness; in-game observation is the final word.
- 🏷️ **<span style="color:#59f0dc">Version Bump:</span>** `TacoTip.toc` and the harness version pins move to `0.9.2`; the extra first-login line prints once on upgrade and the saved configuration is carried over as before.

---

## <span style="color:#e67e23">What's New in v0.9.1</span>

- 🔎 **<span style="color:#59f0dc">New Inspect-Queue Diagnostics:</span>** `/tt diag` now reports two additional additive counters — queue-overflow drops and queue-drain drops — so a diagnostic session can show how often the automatic inspect queue shed a request. Observability only: no gate, throttle, or timing behavior changes.
- 🧪 **<span style="color:#59f0dc">New Regression Pins:</span>** The test harness now pins the one-argument `CanInspect` call contract; the inspect-queue mechanics (the 25-entry cap sheds the *oldest* queued entry and counts it, `mouseover` keeps the tail through later requests, a re-hover bumps the current hover to the tail, and an unserved queued entry is counted as a drain-shed); and the saved-variable migration/sanitize behavior for the tooltip mover position (an upgrade clears the exact legacy `{TOPLEFT,TOPLEFT,0,0}` dot and bumps `conf_version`, a same-version load does not re-clear it, and per-load sanitize drops nil-offset/non-table shapes while a valid position survives). Pinned in the harness; not yet observed in game.
- 🔤 **<span style="color:#59f0dc">Internal Hygiene:</span>** One tooltip separator literal used at two render sites in `main.lua` is hoisted into a single pre-formatted constant (byte-identical output), and two in-source comments in `Libs/LibForeverInspector` now state the actual shipped inspect-error-suppressor coverage (Classic Era **and** TBC Anniversary, not the other three families). Zero behavioral changes.
- 🏷️ **<span style="color:#59f0dc">Version Bump:</span>** `TacoTip.toc` and the harness version pins move to `0.9.1`; the extra first-login line prints once on upgrade and the saved configuration is carried over as before.

---

## <span style="color:#e67e23">What's New in v0.9.0</span>

- ⚡ **<span style="color:#59f0dc">Tooltip Render Optimization & Markup Caching:</span>** Class icon atlas markups, pre-spaced faction and PVP badges, and group role icons are now memoized and pre-formatted. Integer color hashing eliminates repetitive color code formatting, and hostility difficulty colors are cached by level, significantly reducing string allocations and garbage collection during high-frequency tooltip hover renders.
- 📏 **<span style="color:#59f0dc">Power-Bar Anchor Alignment:</span>** Corrected a layout bug where the power bar's vertical offset was inverted when the health bar was enabled, causing it to render inside the tooltip body over the text lines. The power bar now docks cleanly at `-9` below the health bar and `-1` when standalone.
- 🏆 **<span style="color:#59f0dc">Leaderboard Slash Forwarding:</span>** Intercepts `/tt lb`, `/tt rank`, `/tt ranks`, and `/tt leaderboard` in the main options handler and forwards them to TacoTip Extras' server leaderboard (`TacoTipExtrasToggleLeaderboard`) instead of opening the configuration menu.
- 🛡️ **<span style="color:#59f0dc">Protected API Resilience:</span>** `SetClampRectInsets` is now wrapped with safe error containment and bypasses execution during combat lockdown, safeguarding against protected function taint exceptions.
- 🎨 **<span style="color:#59f0dc">Cold-Boot Tooltip Border Reliability:</span>** Directly tints Blizzard's native `NineSlice` border (`SetBorderColor`) and `SetBackdropBorderColor` alongside the custom overlay frame, ensuring class-colored tooltip borders render reliably on first boot across all five client families without requiring a UI reload.
- 🎯 **<span style="color:#59f0dc">TBC Inspect Range Reliability:</span>** Restores distance-first inspection gating and the scoped probe error suppressor on TBC Anniversary, eliminating out-of-range red UI error text and vocal sound errors when hovering uncached players beyond inspect distance, while keeping normal gameplay errors and manual inspections fully intact.

---

## ✨ <span style="color:#e67e23">Key Features & Highlights</span>

1. ⚔️ **<span style="color:#59f0dc">Accurate GearScore & Average Item Level:</span>**
   - **Instant Calculation:** Calculates authentic GearScore and average item level (iLvl) for player units upon hover and target selection.
   - **Adaptive Quality Brackets:** Client-tailored quality color bands automatically adapt to your expansion (**200 for Classic Era and WoW Forever, 400 for TBC, 1000 for Titanforge and Retail**).
   - **Item Tooltip Scoring:** Displays individual item GearScore, item level, and HunterScore directly on equipment tooltips.
   - **Titan's Grip & Hunter Normalization:** Exact slot mod math accounts for standalone 2H weapons (2.0x SlotMOD), Titan's Grip dual-wielding (0.5 dampening), and Hunter weapon scaling.

2. 👤 **<span style="color:#59f0dc">Live 3D & 2D Character Portraits:</span>**
   - **Interactive 3D Models:** Render a live 3D character portrait right beside the unit tooltip.
   - **2D Class Badge Fallback:** Lightweight 2D portrait mode when you prefer minimal visuals.
   - **Full Portrait Controls:** Independently adjust portrait scale, 3D camera zoom level (zoom in on the character's face), or invert the portrait to dock to either side of the tooltip.

3. 📜 **<span style="color:#59f0dc">Talents, Specializations & Dual-Spec:</span>**
   - **Specialization Names & Icons:** Displays player specialization name and spec icon badge directly on the tooltip.
   - **Talent Point Distribution:** Shows exact talent trees (e.g., `17/0/44`) with dual-spec support and clear visual dimming for inactive talent groups.
   - **Static High-Res Talent Icons:** Ported icon tables ensure crisp specialization and talent artwork across all Classic expansions.

4. 💎 **<span style="color:#59f0dc">Pawn Stat Scoring Integration:</span>**
   - **Automatic Detection:** Seamlessly integrates with Pawn whenever it is installed.
   - **Zero-Spam Scale Resolution:** Safely queries Pawn's scale database for your class and specialization without producing chat window warnings.
   - **Custom Upgrade Tooltips:** Displays Pawn upgrade percentages and spec scores directly on player and item tooltips.

5. 🎛️ **<span style="color:#59f0dc">Customizable Layout & Tooltip Mover:</span>**
   - **Interactive Mover:** Type `/tt custom` to move your tooltip anywhere on the screen with a draggable visual anchor.
   - **Anchor Options:** Choose between custom on-screen positioning, docking to your mouse cursor, or standard Blizzard default placement.
   - **Visual Styling:** Customize fonts, font sizes, maximum tooltip width, class-colored borders, subtle class background tints, and section divider lines.
   - **Health & Power Bars:** Optional embedded health and mana/energy/rage status bars beneath the tooltip with customizable bar textures.

6. 🚀 **<span style="color:#59f0dc">Zero-Lag / Zero-Taint Performance:</span>**
   - **High-Frequency Memory Pooling:** Static pooled record buffers eliminate garbage collection stutter during 40-man raids and crowded capitals.
   - **Taint-Free Game Menus:** Sound suppression cleanly mutes out-of-range inspect noises without detouring `_G.PlaySound`, guaranteeing Game Menu buttons (Exit Game / Logout) are never blocked by UI execution taint.

---

## ⌨️ <span style="color:#e67e23">Slash Commands</span>

Configure TacoTip quickly from your chat bar using `/tt`, `/tacotip`, `/tip`, or `/gearscore`:

| Command | Action |
| :--- | :--- |
| **<span style="color:#59f0dc">/tt</span>** or **<span style="color:#59f0dc">/tacotip</span>** | Opens the TacoTip configuration menu. |
| **<span style="color:#59f0dc">/tt custom</span>** | Shows the draggable visual mover to place your tooltips anywhere on screen. |
| **<span style="color:#59f0dc">/tt save</span>** | Saves the current position of the tooltip mover. |
| **<span style="color:#59f0dc">/tt default</span>** | Disables custom positioning and restores Blizzard's default tooltip anchor. |
| **<span style="color:#59f0dc">/tt anchor &lt;point&gt;</span>** | Sets custom anchor point (`topleft`, `topright`, `bottomleft`, `bottomright`). |
| **<span style="color:#59f0dc">/tt reset</span>** | Restores all configuration settings to their factory defaults. |
| **<span style="color:#59f0dc">/tt diag</span>** | Opens the live diagnostic telemetry panel to inspect target range and addon health. |

---

## ⚙️ <span style="color:#e67e23">Configuration Guide</span>

Access settings at any time by pressing **Esc → Options → AddOns → TacoTip** or by typing `/tt`.

- **<span style="color:#59f0dc">Root Page (TacoTip):</span>**
  - **Quick Actions:** Open the visual tooltip mover or restore factory settings.
  - **Language Selector:** Override the addon language to any of the 11 supported locales.
  - **Combat Suppression:** Automatically hides heavy inspection overlays while engaged in combat.
  - **Status Summary:** Live overview of your current tooltip anchor mode, active language, and overlay states.

- **<span style="color:#59f0dc">Tooltips Page (/tt → Tooltips):</span>**
  - **Scaling & Presets:** Global tooltip scale (50%–200%), Portrait scale (50%–200%), style presets, font selection, and max width limiter.
  - **Player & Unit Content:** Toggle player titles, guild names, guild ranks, realm, talents, targets, role icons, and faction/PvP badges.
  - **Character Portrait:** Enable 3D or 2D portraits, adjust portrait zoom, and flip portrait docking side.
  - **Bars & Visual Styling:** Health and power bars, class-colored borders, custom background tints, border thickness, and SharedMedia textures.

- **<span style="color:#59f0dc">Positioning Page (/tt → Positioning):</span>**
  - Fine-tune exact X/Y coordinate sliders for tooltips and character frame overlays.
  - Enable or disable mouse cursor anchoring for world units and action spells.

- **<span style="color:#59f0dc">Character & Inspect Page (/tt → Character / Inspect):</span>**
  - Toggle GearScore and average item level text badges on your character paperdoll and inspection window.
  - Unlock info positions to drag overlays to custom locations on character frames.

---

## ❓ <span style="color:#e67e23">Frequently Asked Questions (FAQ)</span>

**<span style="color:#59f0dc">Q: Why doesn't a player's GearScore show immediately when I hover them?</span>**
**A:** World of Warcraft limits gear inspection to players within inspect range (approx. 20–30 yards depending on client version). When a player is in range, TacoTip queries their equipment and caches the result for 5 minutes. If a player is out of range, TacoTip smoothly falls back to showing their name, guild, and level without lagging your game.

**<span style="color:#59f0dc">Q: How do I change the size of my tooltips?</span>**
**A:** Open settings (`/tt`), click **Tooltips** on the left menu, and use the **Global tooltip scale** slider at the top of the page. You can adjust the scale anywhere from 50% to 200%.

**<span style="color:#59f0dc">Q: Can I move where tooltips appear?</span>**
**A:** Yes! Type `/tt custom` in chat. A green anchor button will appear on your screen. Drag it to your desired location and click **Save**. To reset back to default placement, type `/tt default`.

**<span style="color:#59f0dc">Q: Something seems off with an inspection. How can I check what is happening?</span>**
**A:** Target or hover the unit and type `/tt diag`. TacoTip will display real-time yardage, inspect capability flags (`CanInspect`, `CheckInteractDistance`), cache status, inspect queue depth, and any recent error history.

---

## 🩺 <span style="color:#e67e23">Troubleshooting & Diagnostics</span>

If something looks inert or an inspection fails to appear, run this command first:

```bash
/tacotip diag
```

It opens TacoTip's comprehensive live telemetry HUD:

- **Active Unit Context:** Real-time inspect flags (`CanInspect`, `CheckInteractDistance`), live yardage, cache status, and in-flight queue state for your target or mouseover unit.
- **Error History Ring Buffer:** Records the last 15 caught errors across all subsystems with relative timestamps.
- **Inspect Engine Health:** Displays queue depth, pending duration, cache size, timeouts, and recent refusal reasons.
- **Load Status:** Verifies that all modules loaded cleanly without raising Lua errors.

---

## 🌍 <span style="color:#e67e23">Localization</span>

TacoTip ships with localized translations for all 11 official World of Warcraft languages:

- **English** (`enUS` / `enGB`)
- **German** (`deDE`)
- **Spanish** (`esES` & `esMX`)
- **French** (`frFR`)
- **Italian** (`itIT`)
- **Korean** (`koKR`)
- **Brazilian Portuguese** (`ptBR`)
- **Russian** (`ruRU`)
- **Simplified Chinese** (`zhCN`)
- **Traditional Chinese** (`zhTW`)

---

## 📜 <span style="color:#e67e23">Credits & License</span>

TacoTip is distributed under the **MIT License**. The full text ships in [LICENSE](LICENSE).

Bundled third-party libraries under `Libs/` keep their **own** licenses and are **not** covered by TacoTip's MIT terms:

| Library | License | Author |
| :--- | :--- | :--- |
| `LibStub` | Public Domain | Kaelten, Cladhaire, ckknight, Mikk, Ammo, Nevcairiel, joshborke |
| `CallbackHandler-1.0` | MIT | Icedragon and contributors |
| `LibDetours-1.0` | MIT | kebabstorm |
| `LibForeverInspector` | MIT | AcidBomb (part of this project) |

Full attribution and license notices are available in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
GearScore calculation behavior derives from GearScoreTBCClassic; see the notices in [TacoTip Extras' THIRD_PARTY_NOTICES.md](TacoTip_Extras/THIRD_PARTY_NOTICES.md).

Author and maintainer: **AcidBomb (Pilsung)**.
