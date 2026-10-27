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
version: 0.8.8
author: AcidBomb
maintainer: AcidBomb (Pilsung)
license: MIT
curseforge_id: 1555962
project_url: https://www.curseforge.com/wow/addons/tacotip-gearscore
clients: [Classic Era / SoD, TBC Anniversary, WotLK Titanforge, WoW Forever, Retail]
interfaces: ["11509", "20506", "38002", "16001", "120105"]
tags: [tooltip, gearscore, gear-score, 3d-portrait, class-colors, talents, pawn, inspect, enhancement, cross-engine]
requires: [LibStub, CallbackHandler-1.0, LibDetours-1.0, Pawn, LibSharedMedia-3.0, SharedMedia]
status: released
updated: 2026-10-26
```

**TacoTip** is the premier, all-in-one tooltip enhancement for World of Warcraft. Built with a unified cross-engine architecture, a single installation runs seamlessly across **every** World of Warcraft client family — from Classic Era and Season of Discovery to The Burning Crusade Anniversary, WotLK Titanforge, WoW Forever, and Retail Live:

- **<span style="color:#59f0dc"><span style="text-decoration:underline">CurseForge</span></span>** — <https://www.curseforge.com/wow/addons/tacotip-gearscore> (this add-on)

- **<span style="color:#e67e23"><span style="text-decoration:underline">Companion App</span></span>** — [TacoTip Extras](https://www.curseforge.com/wow/addons/tacotip-extras/preview) ![TacoTip Extras](https://media.forgecdn.net/attachments/2065/485/2-png.png) *(Guild rank browser, player gear leaderboard & historical stat tracking)*

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

## <span style="color:#e67e23">What's New in v0.8.8</span>

- **<span style="color:#59f0dc">Inspection Cache Correctness:</span>** A gear swap whose item links are still arriving from the server can no longer be scored as a mix of old and new gear, and an emptied slot no longer keeps its old score. The last complete GearScore/iLvl stays visible while the refresh runs, out-of-range gear changes are marked stale instead of being served as fresh for five minutes, and the session cache is bounded.
- **<span style="color:#59f0dc">GearScore Item Data:</span>** GearScore no longer waits on the client to load item data for inspected gear. Unresolved links are requested explicitly (throttled per item), so the score line appears with the real numbers instead of staying absent for gear the client has never cached.
- **<span style="color:#59f0dc">Enterprise `/tt diag`:</span>** The report is now structured and fault-isolated: a verdict line first, fixed sections (environment, active unit, tooltip, inspect queue, counters, inspect frame, errors, problems), session uptime and failure rates, and stable paste-friendly ordering. Benign GearScore item-load completions are their own counter instead of "unit resolution failed", the cache row shows the record that actually exists (age, stale, incomplete, GS, iLvl, spec), the portrait row reports the real 2D/3D mode, and one broken section can no longer swallow the rest of the report.
- **<span style="color:#59f0dc">Library Alias Safety:</span>** The bundled inspector no longer takes the `LibClassicInspector` name from another add-on that already loaded it.
- **<span style="color:#59f0dc">Release Hygiene:</span>** Unloaded vendored libraries are no longer shipped or linted; the package and lint gates are green again.

---

## <span style="color:#e67e23">What's New in v0.8.7</span>

- **<span style="color:#59f0dc">Global Tooltip & Portrait Scalers at Top of Settings:</span>** Instantly resize your tooltips with the new **Global tooltip scale** slider (50%–200%) and **Portrait scale** slider positioned prominently at the very top of the Tooltips settings page (`/tt` → Tooltips).
- **<span style="color:#59f0dc">Streamlined Tooltip Settings Layout:</span>** Completely redesigned settings panel with 6 organized sections, symmetrical two-column unit options, and real-time control dependency updates.
- **<span style="color:#59f0dc">Deep In-Game Telemetry (`/tt diag`):</span>** Live inspection diagnostics that evaluate your active target or mouseover unit in real-time, displaying live yardage, inspect flags, queue depth, cache status, and a 15-entry error history ring buffer.
- **<span style="color:#59f0dc">Mover & Input Safety:</span>** Improved drag button interaction prevents accidental position cycling on mouse-down and ensures rock-solid frame positioning during rapid window dragging.

---

## <span style="color:#e67e23">Key Features & Highlights</span>

1. **<span style="color:#59f0dc">Accurate GearScore & Average Item Level:</span>**
   - **Instant Calculation:** Calculates authentic GearScore and average item level (iLvl) for player units upon hover and target selection.
   - **Adaptive Quality Brackets:** Client-tailored quality color bands automatically adapt to your expansion (**200 for Classic Era and WoW Forever, 400 for TBC, 1000 for Titanforge and Retail**).
   - **Item Tooltip Scoring:** Displays individual item GearScore, item level, and HunterScore directly on equipment tooltips.
   - **Titan's Grip & Hunter Normalization:** Exact slot mod math accounts for standalone 2H weapons (2.0x SlotMOD), Titan's Grip dual-wielding (0.5 dampening), and Hunter weapon scaling.

2. **<span style="color:#59f0dc">Live 3D & 2D Character Portraits:</span>**
   - **Interactive 3D Models:** Render a live 3D character portrait right beside the unit tooltip.
   - **2D Class Badge Fallback:** Lightweight 2D portrait mode when you prefer minimal visuals.
   - **Full Portrait Controls:** Independently adjust portrait scale, 3D camera zoom level (zoom in on the character's face), or invert the portrait to dock to either side of the tooltip.

3. **<span style="color:#59f0dc">Talents, Specializations & Dual-Spec:</span>**
   - **Specialization Names & Icons:** Displays player specialization name and spec icon badge directly on the tooltip.
   - **Talent Point Distribution:** Shows exact talent trees (e.g., `17/0/44`) with dual-spec support and clear visual dimming for inactive talent groups.
   - **Static High-Res Talent Icons:** Ported icon tables ensure crisp specialization and talent artwork across all Classic expansions.

4. **<span style="color:#59f0dc">Pawn Stat Scoring Integration:</span>**
   - **Automatic Detection:** Seamlessly integrates with Pawn whenever it is installed.
   - **Zero-Spam Scale Resolution:** Safely queries Pawn's scale database for your class and specialization without producing chat window warnings.
   - **Custom Upgrade Tooltips:** Displays Pawn upgrade percentages and spec scores directly on player and item tooltips.

5. **<span style="color:#59f0dc">Customizable Layout & Tooltip Mover:</span>**
   - **Interactive Mover:** Type `/tt custom` to move your tooltip anywhere on the screen with a draggable visual anchor.
   - **Anchor Options:** Choose between custom on-screen positioning, docking to your mouse cursor, or standard Blizzard default placement.
   - **Visual Styling:** Customize fonts, font sizes, maximum tooltip width, class-colored borders, subtle class background tints, and section divider lines.
   - **Health & Power Bars:** Optional embedded health and mana/energy/rage status bars beneath the tooltip with customizable bar textures.

6. **<span style="color:#59f0dc">Zero-Lag / Zero-Taint Performance:</span>**
   - **High-Frequency Memory Pooling:** Static pooled record buffers eliminate garbage collection stutter during 40-man raids and crowded capitals.
   - **Taint-Free Game Menus:** Sound suppression cleanly mutes out-of-range inspect noises without detouring `_G.PlaySound`, guaranteeing Game Menu buttons (Exit Game / Logout) are never blocked by UI execution taint.

---

## <span style="color:#e67e23">Slash Commands</span>

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

## <span style="color:#e67e23">Configuration Guide</span>

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

## <span style="color:#e67e23">Frequently Asked Questions (FAQ)</span>

**<span style="color:#59f0dc">Q: Why doesn't a player's GearScore show immediately when I hover them?</span>**  
**A:** World of Warcraft limits gear inspection to players within inspect range (approx. 20–30 yards depending on client version). When a player is in range, TacoTip queries their equipment and caches the result for 5 minutes. If a player is out of range, TacoTip smoothly falls back to showing their name, guild, and level without lagging your game.

**<span style="color:#59f0dc">Q: How do I change the size of my tooltips?</span>**  
**A:** Open settings (`/tt`), click **Tooltips** on the left menu, and use the **Global tooltip scale** slider at the top of the page. You can adjust the scale anywhere from 50% to 200%.

**<span style="color:#59f0dc">Q: Can I move where tooltips appear?</span>**  
**A:** Yes! Type `/tt custom` in chat. A green anchor button will appear on your screen. Drag it to your desired location and click **Save**. To reset back to default placement, type `/tt default`.

**<span style="color:#59f0dc">Q: Something seems off with an inspection. How can I check what is happening?</span>**  
**A:** Target or hover the unit and type `/tt diag`. TacoTip will display real-time yardage, inspect capability flags (`CanInspect`, `CheckInteractDistance`), cache status, inspect queue depth, and any recent error history.

---

## <span style="color:#e67e23">Troubleshooting & Diagnostics</span>

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

## <span style="color:#e67e23">Localization</span>

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

## <span style="color:#e67e23">Credits & License</span>

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
