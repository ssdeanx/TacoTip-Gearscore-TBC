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
version: 0.9.2
author: AcidBomb
maintainer: AcidBomb (Pilsung)
license: MIT
curseforge_id: 1555962
project_url: https://www.curseforge.com/wow/addons/tacotip-gearscore
clients: [Classic Era / SoD, TBC Anniversary, WotLK Titanforge, WoW Forever, Retail]
interfaces: ["11509", "20506", "38002", "16001", "120105"]
tags: [tooltip, gearscore, gear-score, 3d-portrait, class-colors, talents, pawn, inspect, enhancement, cross-engine]
requires: [LibStub, CallbackHandler-1.0, LibDetours-1.0, Pawn, LibSharedMedia-3.0, SharedMedia]
status: pending in-game verification
updated: 2026-11-05
```

**TacoTip** is the premier, all-in-one tooltip enhancement for World of Warcraft. Built with a unified cross-engine architecture, a single installation runs seamlessly across **every** World of Warcraft client family — from Classic Era and Season of Discovery to The Burning Crusade Anniversary, WotLK Titanforge, WoW Forever, and Retail Live:

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
> 🎉 **<span style="color:#2ecc71">130,000+ Downloads Milestone:</span>** A heartfelt thank you to the entire community! We just surpassed **130,000 downloads** and are growing faster than ever. Your continuous feedback, testing, and support have made all of this rapid progress possible — thank you for making TacoTip your go-to tooltip addon!

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
