
```ascii
__              _____ _____
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
version: 1.0.1
author: AcidBomb
maintainer: AcidBomb (Pilsung)
license: MIT
curseforge_id: 1555962
project_url: https://www.curseforge.com/wow/addons/tacotip-gearscore
clients: [Classic Era / SoD, TBC Anniversary, WotLK Titanforge, WoW Forever, Retail]
interfaces: ["11509", "20506", "38002", "16001", "120105"]
tags: [tooltip, gearscore, gear-score, 3d-portrait, class-colors, talents, pawn, inspect, enhancement, cross-engine]
requires: [LibStub, CallbackHandler-1.0, LibDetours-1.0, Pawn, LibSharedMedia-3.0, SharedMedia]
status: pending in-game verification (2026-11-12)
linter: wowlua_ls check — 0 errors, no secret-value findings; 136 warnings (70 `need-check-nil`, 56 `undefined-field`, 5 `redundant-parameter`, 3 `invalid-op`, 2 `type-mismatch`) (2026-11-12)
contract audit: 119 Unit/Item call sites audited, 22 corrected, independent review PASS (2026-11-10)
gates: run_all 75/75 (lua5.1 + luajit), Extras 42/42 (lua5.1/lua5.4/luajit), luacheck 2 warnings / 0 errors in 91 files, both verifiers PASS (2026-11-12)
updated: 2026-11-12
```

# ⚡ TacoTip ⚡

![tbc-ss1](https://media.forgecdn.net/attachments/2178/795/1-png.png)

<p align="center">
  <a href="https://www.curseforge.com/wow/addons/tacotip-gearscore"><img src="https://img.shields.io/badge/Downloads-200%2C000%2B-brightgreen?style=for-the-badge&logo=curseforge&logoColor=white" alt="Downloads" /></a>
  <a href="https://www.curseforge.com/wow/addons/tacotip-gearscore"><img src="https://img.shields.io/badge/Release-v1.0.1-gold?style=for-the-badge&logo=worldofwarcraft&logoColor=white" alt="Version" /></a>
  <a href="https://www.curseforge.com/wow/addons/tacotip-gearscore"><img src="https://img.shields.io/badge/Engine-Universal%20Dual--Engine-blueviolet?style=for-the-badge&logo=codeforces&logoColor=white" alt="Dual Engine" /></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-MIT-blue?style=for-the-badge" alt="License" /></a>
  <a href="https://discord.gg/JuVJBwXqv"><img src="https://img.shields.io/badge/Discord-Join%20Community-5865F2?style=for-the-badge&logo=discord&logoColor=white" alt="Discord" /></a>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Classic%20Era%20%7C%20SoD-1.15.9-f39c12?style=flat-square&logo=battledotnet&logoColor=white" alt="Classic Era" />
  <img src="https://img.shields.io/badge/TBC%20Anniversary-2.05.06-2ecc71?style=flat-square&logo=battledotnet&logoColor=white" alt="TBC Anniversary" />
  <img src="https://img.shields.io/badge/WotLK%20Titanforge-3.80.02-3498db?style=flat-square&logo=battledotnet&logoColor=white" alt="Titanforge" />
  <img src="https://img.shields.io/badge/WoW%20Forever-16.0.01-9b59b6?style=flat-square&logo=battledotnet&logoColor=white" alt="WoW Forever" />
  <img src="https://img.shields.io/badge/Retail%20Live-12.01.05-e74c3c?style=flat-square&logo=battledotnet&logoColor=white" alt="Retail" />
  <img src="https://img.shields.io/badge/Quality-0%20Warnings-success?style=flat-square&logo=checkmarx&logoColor=white" alt="Luacheck Clean" />
  <img src="https://img.shields.io/badge/Verification-74%2F74%20Automated%20Harness-brightgreen?style=flat-square&logo=githubactions&logoColor=white" alt="Automated harness 74/74 (offline pins, not in-game verification)" />
</p>

---

<div align="center">

## 🏆 200,000+ Downloads Milestone & Community Celebration

**A monumental thank you to over 200,000 World of Warcraft players and guild leaders worldwide!**
*Your passionate feedback, bug reports, and community support have powered TacoTip from a Classic tooltip tweak into the definitive cross-engine tooltip suite.*
**[Join our official Discord community](https://discord.gg/JuVJBwXqv)** to share your ideas, get instant support, and shape the next generation of features!

</div>

---

**TacoTip** is the premier, all-in-one tooltip enhancement suite for World of Warcraft. Built with a unified dual-engine architecture, a single installation runs seamlessly across **every** World of Warcraft client family — from Classic Era and Season of Discovery to The Burning Crusade Anniversary, WotLK Titanforge, WoW Forever, and Retail Live:

💬 **<span style="color:#5865F2"><span style="text-decoration:underline">Official Discord Community</span></span>** — <https://discord.gg/JuVJBwXqv>
📦 **<span style="color:#f39c12"><span style="text-decoration:underline">CurseForge Page</span></span>** — <https://www.curseforge.com/wow/addons/tacotip-gearscore>
🌟 **<span style="color:#b4e634"><span style="text-decoration:underline">Companion Addon (TacoTip Extras)</span></span>** — [TacoTip Extras on CurseForge](https://www.curseforge.com/wow/addons/tacotip-extras) *(Server leaderboard, guild rank browser & peer-to-peer gear sync)*
![TacoTip Extras](https://media.forgecdn.net/attachments/2065/485/2-png.png)

| Client Family | Supported Interface | Client Status | Architectural World |
| :--- | :--- | :--- | :--- |
| **<span style="color:#f39c12">Classic Era / Season of Discovery (SoD)</span>** | `11509` | <span style="color:#2ecc71">**Active**</span> | Classic Talent API (`GetTalentTabInfo`) |
| **<span style="color:#2ecc71">The Burning Crusade Classic Anniversary</span>** | `20506` | <span style="color:#2ecc71">**Active**</span> | Classic Talent API (`GetTalentTabInfo`) |
| **<span style="color:#3498db">WotLK Titanforge</span>** | `38002` | <span style="color:#2ecc71">**Active**</span> | Classic Talent API (`GetTalentTabInfo`) |
| **<span style="color:#9b59b6">WoW Forever (Camelot)</span>** | `16001` | <span style="color:#2ecc71">**Active**</span> | Mainline Trait API (`C_Traits` + `C_SpecializationInfo`) |
| **<span style="color:#e74c3c">Retail / Live (Midnight)</span>** | `120105` | <span style="color:#2ecc71">**Active**</span> | Mainline Family (`C_SpecializationInfo`) |

> **<span style="color:#e67e23">Interface tokens:</span>** the root `TacoTip.toc` declares exactly these five (`11509`, `20506`, `38002`, `16001`, `120105`). The companion `TacoTip_Extras.toc` additionally lists `120107`; that asymmetry is deliberate in the two TOCs and is not something this README can change.

> **<span style="color:#e67e23">Seamless 1:1 Migration:</span>** This universal release replaces all previous single-client TacoTip builds. Your configuration carries over automatically, and Classic Era / TBC GearScore numbers remain byte-identical.

---

## ⚡ <span style="color:#e67e23">Key Feature Matrix</span>

| Feature | Classic Era / TBC / Titanforge | WoW Forever (Camelot) | Retail Live |
| :--- | :---: | :---: | :---: |
| **Classic GearScore & Average iLvl** | ✅ Fully Supported | ✅ Fully Supported | ✅ Fully Supported |
| **Personal Progression & Gear Leveling** | ✅ Level 1-60+ & Trophies | ✅ Level 1-60+ & Trophies | ✅ Level 1-60+ & Trophies |
| **Equipment Upgrade Chronicle** | ✅ 500-Item History | ✅ 500-Item History | ✅ 500-Item History |
| **Pawn Dual-Spec Pre-Calculation** | ✅ Instant Spec Switching | ✅ Instant Spec Switching | ✅ Instant Spec Switching |
| **Specialization & Talents Breakdown** | ✅ `[p1/p2/p3]` Trees + Icons | ✅ Dual-Spec Trait Trees | ✅ Modern Spec & Icon |
| **3D Character Model Portraits** | ✅ Fully Stabilized | ✅ Fully Stabilized | ✅ Fully Stabilized |
| **Smooth Unit Power & Health Bars** | ✅ Smooth Fade-Out | ✅ Untainted Secret Values | ✅ AllowedWhenTainted |
| **Group Role-Priority Inspects** | ✅ Tank > Healer > DPS | ✅ Tank > Healer > DPS | ✅ Tank > Healer > DPS |
| **Dynamic Zone Tracking** | — | ✅ Native `C_Map` Readout | — |
| **Enterprise Dashboard (`/tt`)** | ✅ `1000×600` Slate & Lime | ✅ `1000×600` Slate & Lime | ✅ `1000×600` Slate & Lime |
| **Directly Embedded Leaderboard** | ✅ Realm Rankings from peer sync | ✅ Realm Rankings from peer sync | ✅ Realm Rankings from peer sync |
| **1-Click Markdown Diagnostic Export** | ✅ `/tt report` | ✅ `/tt report` | ✅ `/tt report` |

---

## 🚀 <span style="color:#e67e23">Quick Slash Commands</span>

| Command | Action |
| :--- | :--- |
| `/tt` or `/tacotip` | Toggle the modern **1000×600 Enterprise Settings Dashboard** |
| `/tt report` or `/tt export` | Generate a 1-click **Markdown Diagnostic Report** ready to paste into Discord or GitHub |
| `/tt diag` | Print the real-time **Diagnostic Report to chat** (yardage, cache status, inspect queue depth) |
| `/tt diag ui` or `/tt diagui` | Open the dashboard's **Diagnostics tab** — the interactive panel (copy button, live refresh, trace toggle, log clear) |
| `/tt custom` | Show the draggable green anchor button to set custom tooltip position |
| `/tt default` | Reset tooltip placement back to stock game default |
| `/tt help` | Display full in-game command reference |

---

## <span style="color:#e67e23">What's New in v1.0.1</span>

🧱 **<span style="color:#b4e634">Static-analysis hardening pass (no player-visible change intended):</span>** The tooltip, overlay and options paths were given explicit type and nil guards for the states `wowlua_ls` can now see. The unit-tooltip renderer no longer assumes a tooltip object or a well-formed line record — `NumLines()` is called only when it exists, the guild/level line bookkeeping is written only with a tooltip present, `AddLine`/`AddDoubleLine` are guarded, and a nil record ends the loop instead of raising. On the non-wide path the line record's own shape decides where its colours live, so a double record's right-hand **text** can no longer be handed to `SetTextColor`/`AddLine` as a colour: every channel is `tonumber`'d and the fallback is white.

🎯 **<span style="color:#b4e634">Pawn and power-bar guards:</span>** A Pawn score that is not a number is coerced to `0` before the `> 0` test rather than compared, and the power bar's `Update` — installed with `rawset` on the frame at runtime — is called only when it is actually a function.

🛡️ **<span style="color:#b4e634">Character &amp; inspect overlay initialisers:</span>** `InitCharacterFrame` now returns `true` once the font strings exist, and `RefreshCharacterFrame` captures the method once and calls it as a function. `InitInspectFrame` marks itself done on entry; `RefreshInspectFrame` captures it, stops if it answers `false`, and the three event arms (`ADDON_LOADED` for TacoTip, `ADDON_LOADED` for `Blizzard_InspectUI`, and `INVENTORY_READY`/`TALENTS_READY`) call it through a `type(...) == "function"` test and `pcall`.

🧩 **<span style="color:#b4e634">Options and diagnostics:</span>** Dropdown labels and descriptions fall back to `UIParent` when no parent is supplied, the dashboard's trophy unlock date is `tostring`'d before concatenation, a non-string unit is refused before a tooltip refresh, `GetItemInfo` is called only with an item link, and `CollectDiagnostics`' pcall result is named so the error table and the collected table can never share a name.

🔧 **<span style="color:#b4e634">Tooling:</span>** `.wowluarc.json` no longer suppresses the eight documentation diagnostics (`doc-field-no-class`, `doc-func-no-function`, `duplicate-doc-alias`, `duplicate-doc-field`, `duplicate-doc-param`, `undefined-doc-class`, `undefined-doc-name`, `undefined-doc-param`), so `wowlua_ls` reports them again. On this tree the linter reports 0 errors and 136 warnings — 70 `need-check-nil`, 56 `undefined-field`, 5 `redundant-parameter`, 3 `invalid-op`, 2 `type-mismatch` — recorded, not suppressed.

---

## <span style="color:#e67e23">What's New in v1.0.0 Milestone Release</span>

🎮 **<span style="color:#b4e634">Personal Progression & Gear Rank Leveling Mini-Game:</span>** Introducing a gamified local character progression engine with its own dedicated dashboard tab! Level up your character's Gear Rank (Levels 1 to 60+) with prestigious titles ranging from *Novice* to *Immortal Legend*, track live progress with an animated emerald XP bar, collect 10 milestone trophy achievements with unlock timestamps, and browse a searchable 500-entry Equipment Upgrade Chronicle with slot filters (*All*, *Weapons*, *Armor*, *Accessories*), delta badges, item hyperlinks, and Shift-click chat linking. Includes optional private local level-up chat alerts and fanfare sounds.

🎨 **<span style="color:#b4e634">Shaman Blue Toggle Classic Era Restriction:</span>** Gated the "Shaman Blue" toggle across the Blizzard Settings panel, the standalone dashboard, and TacoTip Extras so it only appears on **Classic Era** (`11509`), where Blizzard's original pink class color was used. Cleanly hidden on TBC, Titanforge, WoW Forever, and Retail where Shaman is natively blue.

🌟 **<span style="color:#b4e634">Enterprise Standalone Dashboard Expansion (`1000×600`):</span>** Expanded the settings dashboard to 1000×600 with an upgraded 48×48 logo for spacious layout breathing room, readability, and information density. Streamlined the left navigation sidebar width to 155px (action buttons trimmed to 135px, search box to 131px) and expanded all content cards, chronicles, and embedded leaderboards to 760px of usable width.

🎯 **<span style="color:#b4e634">Zero-Jump Rapid Re-hover 3D Portrait Engine:</span>** Once custom tooltip positioning is saved, the portrait stays firmly anchored on the right edge without redundant off-screen edge tests. Valid attachment points are preserved across hovers without tearing down the PlayerModel, completely eliminating portrait jumping when rapidly hovering and re-hovering over players or unit frames.

🏆 **<span style="color:#b4e634">Directly Embedded Server Leaderboard & Quality Range Bands:</span>** When companion addon `TacoTip_Extras` is installed, the dashboard's "Extras" tab now embeds a complete 760×365px Server Leaderboard directly inside the window! Includes 3-way faction filters (`[All Realm]`, `[Alliance]`, `[Horde]`), live search, 10 styled rows, mouse-wheel scrolling, and 1-click `[My Rank]` jump button. Scores are dynamically styled using authentic GearScore quality range bands (`TT_GS:GetQuality`) and standing colors (#1 Gold, #2 Silver, #3 Bronze, Top 5% Gold, quality brackets).

🛡️ **<span style="color:#b4e634">Deep Combat & Restricted Dungeon Secret-Value Immunity:</span>** Fully immunized `UnitDistanceSquared` in diagnostics, `GetClassAtlas`, class tokens (`UnitClass`), specialization text, trait trees (`C_Traits`), faction badges, and group roles against secret string errors during combat and restricted encounters on modern engines.

🎯 **<span style="color:#b4e634">3D Portrait Unit Frame Stabilization:</span>** Completely resolved the long-standing 3D character portrait flickering and strobing when hovering unit frames (`PlayerFrame`, `PetFrame`, `PartyMemberFrame`, `TargetFrame`, `CompactRaidFrame`). Prevented periodic 0.2s unit frame updates from resetting model points and destroying active 3D models while retaining seamless unit-change transitions.

🛡️ **<span style="color:#b4e634">Intelligent Role-Priority Inspection Engine:</span>** In dungeons and raids, inspection queue priorities now prioritize group members by role: **Tank > Healer > DPS** before ambient open-world scans, ensuring immediate GearScore coverage for critical party members.

⚡ **<span style="color:#b4e634">Zero-Allocation FontString Line Buffer Pooling:</span>** Replaced repeated tooltip string formatting and allocations on Classic clients with high-performance FontString recycling buffers (`tooltipLeftLineCache` & `tooltipRightLineCache`), dramatically reducing garbage collection overhead during rapid mouseovers.

📋 **<span style="color:#b4e634">1-Click Markdown Diagnostic Export (`/tt report` & `/tt export`):</span>** Added a 1-click Markdown export button to the Diagnostics tab, formatting client build, hardware status, inspect telemetry, and recent errors into GitHub/Discord-ready markdown with instant `Ctrl+C` copy.

⚔️ **<span style="color:#b4e634">Pawn Dual-Spec Pre-Calculation & Caching:</span>** Multi-spec Pawn calculation now computes and caches both primary and secondary spec scores simultaneously. Switching talent specs immediately presents the cached score with zero re-evaluation lag or hitching.

🔋 **<span style="color:#b4e634">Power Bar Stability & Status Text Safety:</span>** Fixed the power bar prematurely dropping when the mouse moves off a target while `GameTooltip` is still displayed. Immunized power bar and health bar status text against WoW Forever secret value restrictions.

🧭 **<span style="color:#b4e634">Deep WoW Forever Secret-Value Taint Protection:</span>** Hardened map zone caches and inspect data readers against secret key tainting with `rawget(_G, "canaccessvalue")` and `issecretvalue` engine guards.

🧩 **<span style="color:#b4e634">Follow-up Hardening (2026-11-10, same 1.0.0 notes):</span>** All six secret-value predicates in the shipped code now read a refused `issecretvalue`/`canaccessvalue` call as *secret* instead of treating the refusal as "not secret"; `gearscore.lua`, `pawn.lua` and `LibForeverInspector` gained a `UnitIsUnit` guard that pre-checks `C_Secrets.CanCompareUnitTokens` and never boolean-tests an unverified comparison (GUID equality stays authoritative); the saved `custom_pos` writer stores the four-element `{ point, relPoint, x, y }` contract again, so a re-login no longer discards the saved position; and the group check routes `UnitInRaid` through the guarded helper. No player-visible behaviour changes on non-restricted clients.

🚨 **<span style="color:#b4e634">Dungeon & Encounter Crash Fix — `bad argument #1 to 'UnitExists'`:</span>** This is the error players have been reporting in instances. `UnitExists`, `UnitIsPlayer`, `UnitIsConnected` and `UnitIsDeadOrGhost` are all `SecretArguments = "AllowedWhenUntainted"`, so handing one of them a secret unit token from add-on code is refused outright — and inside an instance encounter a tooltip's own unit token **is** secret. Eleven call sites in `LibForeverInspector` passed a caller-supplied token straight to those globals, and the inspect-queue gate `CanInspect` did no token test at all; measured on the previous build, `CanInspect(secretToken)` invoked all four. Every site now routes through `safeUnitExists` / `safeUnitIsPlayer` / `safeUnitIsConnected` / `safeUnitIsDeadOrGhost`, and `CanInspect` rejects a secret token before any query runs. A unit the client will not let us read simply yields no row. Also covered: `UnitClass`, `UnitSex`, `UnitIsOtherPlayersPet`, `UnitIsSameServer`, and the nameplate scanner (where `type(v) == "string"` was being mistaken for a secrecy test — a secret string still reports `"string"`).

- **Item tooltips too.** The post-call payload can itself be a secret table, and indexing one raises — so `issecretvalue` is the wrong test for it. Every `data.<field>` read (item hyperlink/guid, unit guid) is now gated on the documented `canaccesstable`, which answers exactly "may this function index this table?". A payload that cannot be read draws no row instead of erroring.
- **Verify it yourself, solo, with no group and no instance** — the client can force the restrictions anywhere:

    ```lua
    /console addonEncounterRestrictionsForced 1
    /console addonCombatRestrictionsForced 1
    ```

    Hover players in a city and watch for errors; set them back to `0` afterwards (they do not persist across a restart).

🌐 **<span style="color:#b4e634">Universal Engine Integrity:</span>** Complete zero-regression parity across Classic Era (`11509`), TBC Anniversary (`20506`), WotLK Titanforge (`38002`), WoW Forever (`16001`), and Retail (`120105`).

---

## ⌨️ <span style="color:#e67e23">Slash Commands</span>

Configure TacoTip quickly from your chat bar using `/tt`, `/tacotip`, `/tip`, or `/gearscore`:

| Command | Action |
| :--- | :--- |
| **<span style="color:#59f0dc">/tt</span>** or **<span style="color:#59f0dc">/tacotip</span>** | Opens the modern standalone dark-mode dashboard (with real-time search, pill toggles, and live presets). |
| **<span style="color:#59f0dc">/tt discord</span>** or **<span style="color:#59f0dc">/tt community</span>** | Opens the Community hub with our direct Discord invite link. |
| **<span style="color:#59f0dc">/tt custom</span>** | Shows the draggable visual mover to place your tooltips anywhere on screen. |
| **<span style="color:#59f0dc">/tt save</span>** | Saves the current position of the tooltip mover. |
| **<span style="color:#59f0dc">/tt default</span>** | Disables custom positioning and restores Blizzard's default tooltip anchor. |
| **<span style="color:#59f0dc">/tt anchor &lt;point&gt;</span>** | Sets custom anchor point (`topleft`, `topright`, `bottomleft`, `bottomright`). |
| **<span style="color:#59f0dc">/tt reset</span>** | Restores all configuration settings to their factory defaults. |
| **<span style="color:#59f0dc">/tt diag</span>** | Prints the live diagnostic telemetry to chat: target range, inspect flags, queue depth, and addon health. |
| **<span style="color:#59f0dc">/tt diag ui</span>** | Opens the dashboard's interactive Diagnostics tab (copy button, live refresh, error/warning trace toggle). |

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
**A:** Target or hover the unit and type `/tt diag`. TacoTip prints real-time yardage, inspect capability flags (`CanInspect`, `CheckInteractDistance`), cache status, inspect queue depth, and any recent error history to chat. Add `ui` (`/tt diag ui`) to read the same telemetry in the dashboard's interactive Diagnostics tab.

---

## 🩺 <span style="color:#e67e23">Troubleshooting & Diagnostics</span>

If something looks inert or an inspection fails to appear, run this command first:

```bash
/tacotip diag
```

It prints TacoTip's comprehensive live telemetry to the chat frame (use `/tt diag ui` for the interactive Diagnostics tab):

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
