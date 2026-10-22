# Pre-publish test window — time-boxed script (2–3 hours)

The servers are down for maintenance, so the plan is: **test in one focused pass, then upload.** Everything below is ordered by *risk* — the things most likely to be broken first, and the things that cost you the most if they're wrong.

Copy both add-on folders fresh from the repo before you log in. Nothing is committed or staged — you're testing the working tree.

**Rule that governs this whole session:** you cannot test Retail, WoW Forever, TBC or Titanforge before publishing (a publish is a ~100 GB download; you get one shot). So Era is your test client, and the other four ship on the offline proof the audits verified. If Era is clean, publish.

---

## Block A — 15 min — Extras, the feature you just changed

0. **FIRST, the exit-game fix (30 seconds, and it is the whole point of today).**
   Open the **Game Menu** and click **Exit Game**. Then open it again and click
   **Log Out**. Then open it and click Exit Game a third time.
   **Expect: no `ADDON_ACTION_FORBIDDEN`, no red error text, and the game exits
   or logs out normally.** Before the fix, every one of those clicks was refused
   and printed `4x [ADDON_ACTION_FORBIDDEN] AddOn 'TacoTip' tried to call the
   protected function 'UNKNOWN()'`. **If it still refuses, stop and send me the
   exact text** — that is the one defect that blocks the publish, and the stack
   will name the line.
   *Then* run `/tacotip diag` and check the line **"anchor hook failures"** —
   it must read **0**. (It is a new counter: the tooltip's anchor hook is the
   one callback that runs inside a Blizzard call, so a raise there would
   otherwise be invisible.)

1. **Open the leaderboard from the minimap icon.** The **first** click must OPEN it (it used to dismiss an already-open window), the second must close it. Then open it again and confirm it stays.
2. **Open the leaderboard while the Settings panel is open.** It must appear **in front**, not behind.
3. **Click a row → the gear panel.** It must have a **solid dark background** (it was transparent), be readable over the world, and show the slot labels in the client's language.
3b. **Open your CHARACTER panel.** The Extras' **equipment summary** (the small block of gear lines under the paper doll, with the drag handle) must be there and must fill in when your gear is known. It was silently dead on every client until today's fix — if it is missing, say so. Then open the **inspect panel** on a player: the same summary must appear there. `/ttgsdebug` must print **`initialize-failures=0`** — the Extras' module ledger, and the one that would have carried this fault.
4. **Look at the text inside the browser.** "Sorted by GEARSCORE" must have its own line and must not touch the column headers or the "N players | Top N | Avg N" strip. The column headers must line up with the columns under them. The footer ("Your Standing: …") and the Scan now / Top / My Rank buttons must not touch the last row or the progress bar.
5. **Type `/tt lb`.** It must open the **leaderboard**, not TacoTip's options panel. `/tt` alone must still open the options panel.
6. **Open the Extras settings page.** The checkbox area must not overlap — "Restrict Potential, Completion, and warnings to level 70" must not run into "Show server leaderboard rank". The **Comfortable rows** checkbox must look like a normal checkbox and must be clickable (it was a grey box that swallowed its neighbour's click).
7. **Tooltip mode**: confirm the dropdown reads **Detailed**. (New installs default to Detailed; if yours still shows Compact, hit "Reset enhancer settings" once to apply the new default.)
8. **Hover a Shaman.** The class name must read **blue**, not pink. Toggle the new "Shaman Blue" option off and on to confirm it switches.

## Block B — 15 min — main add-on, the feature you just changed

9. **Open the character panel and the inspect panel.** Both must show your **real** GearScore and iLvl, never a standing `0`. Open, close, re-open.
10. **Read the character-panel score text.** It should be **2px larger** (12px) than before and comfortably readable.
11. **Open the Game Menu and quit.** No `ADDON_ACTION_FORBIDDEN`, no error spam. This is the taint fix — it must be clean.
12. **Hover a friendly player**, then an **enemy player**, then a **hostile NPC**: the tooltip must resolve to the right unit each time, and the border must be class-coloured for players and the base colour for NPCs (by design).
13. **Right-click a player with no guild → Inspect.** The inspect frame must open and render fully. No crash. (This is the guild-line fix.)
14. **Walk out of range of a player.** No "Not in Range" popup, and no repeating error. (0.8.3's fix; the range gate is frozen.) **And no error SOUND** — an out-of-range refusal is the one refusal whose sound is muted (today's change; you asked for exactly that, because Classic Era kept spamming "out of range").
    *If a refusal that is **not** about the range happens (a "can't inspect that unit" style error), you will now **hear** it even though no text appears. That is intended too: the text stays swallowed (0.8.3's popup fix) but the sound is not, so the player is told something happened.*

## Block B2 — 10 min — the tooltip surface, after the containment change

The fix wrapped every add-on callback that runs inside a Blizzard frame's script chain in `securecall` — the tooltip's unit/item/spell hooks, the visual clearing, the anchor hook, the character and inspect panes, the power bar. **None of it may be visible.** Check that nothing changed:

21. **Hover a player with a guild.** The tooltip must show the guild line, the class colour and the level line exactly as before — no missing line, no doubled line, no tooltip that fails to appear.
22. **Hover an item, then a spell, then a unit.** Each must show only its own content — the power bar and the class colour must not bleed from one to the next.
23. **Open the character panel and the inspect panel again.** The score and iLvl must repaint on every open (the pane refresh hooks are contained too).
24. **Drag the tooltip with the mover, then save the position.** The position must stick across a `/reload`, **and it must apply to every unit tooltip, not just the unit frames** — hover a player **in the world** (mouseover) as well as one in a party/raid frame. The world hover was the broken class: the client sets the tooltip's anchor *before* it tells the tooltip which unit it is showing, so the addon's gate read it as a menu and left the tooltip at the bottom-right corner. If the tooltip still sits at the bottom-right while the green handle is somewhere else, run `/tacotip diag` **before** reloading and send me the "anchor passthrough" lines.
     - **Portrait side:** with a saved position near the right edge, hover **two different units in a row without reloading** — the first narrow, the second wider (a player with guild/talents/gear is the wide one). The portrait must sit on the tooltip's **left** (fully on screen) whenever the tooltip's right edge is at or past the screen edge, and on its **right** otherwise. "First hover fine, the rest stuck off screen" is the defect this covers; send the two screenshots.
25. **If a tooltip ever looks wrong, run `/tacotip diag` BEFORE you reload** — the counters are the evidence, and a reload clears them.
26. **OPTIONAL — the power bar has never been observed in game.** It is **off by default** (`show_power_bar = false`), so it has never been created on your install; the health bar you see is Blizzard's own, which the add-on keeps because `show_hp_bar` defaults **on**. If you want it verified before publishing: tick **Options → "Unit tooltip content" → Power Bar** (the row under Health Bar), hover a player, and expect a thin bar **9px below the tooltip, directly under the health bar**, coloured by power type, updating as you spend/regain power. Untick it afterwards if you do not want it. Three harness pins cover this path, but this is the only in-game confirmation it would ever have had — so if it does nothing with the box ticked, **that is a defect; send me a screenshot and `/tacotip diag`**.

## Block C — 10 min — diagnostics

15. **Run `/tacotip diag`.** It must print without raising, and its problems list should be empty or explain itself.
16. **Run `/ttgsdebug`** (Extras). It must print the surfaces block with the live counters (driver renders/rows, rank-record errors, row-tooltip errors, score-colour fallbacks, initialize failures). **If it prints nothing, that is a defect — send me the output.**
17. **Toggle "Instant fade"** in the Tooltips options. On Era the client has no instant-fade API, so the option must be **greyed out with an explanation**, and `/tacotip diag` must name the mode. (If it still accepts the toggle silently, send me a screenshot.)
17b. **Confirm the Extras picked the classic family.** `/ttgsdebug` now prints `client-family=… pvp-surface=…`. On Classic Era that line must read **`client-family=classic pvp-surface=classic`**. `mainline` would mean the family split failed; `unknown` means the library's identity was unreadable and the old API fallback decided. If it is not `classic/classic`, send me that line — the leaderboard's PvP rank column depends on it (this is the marker fixed after your "no rated bg on Classic Era" note).

## Block D — 10 min — the sweep

18. **Open every options page** (Tooltips, Positioning, Character & Inspect) and confirm each renders with no overlap and no missing control.
19. **Check the settings survive a `/reload`** — the tooltip mode, the Shaman Blue option, and the scan toggle.
20. **Hover an item** → iLvl, GearScore, and (for a hunter) HunterScore all present and coloured.

---

## If something is wrong — what to send me

| Symptom | Send me |
| :--- | :--- |
| A Lua error pops up | the **full** error text, including the `Interface\AddOns\...` path and line number |
| **The game menu still refuses to exit** | the **full** `ADDON_ACTION_FORBIDDEN` text, and the `/tacotip diag` output (the "anchor hook failures" line) — **do not reload first** |
| A control is missing or misaligned | a **screenshot** of that page |
| A number looks wrong (GS, iLvl, Completion, Potential) | the item/character, the number, and what you expect |
| A tooltip or panel is blank | `/tacotip diag` output **and** `/ttgsdebug` output |
| The browser misbehaves | `/ttgsdebug` output + a screenshot |

**Capture diagnostics BEFORE you `/reload`** — a reload clears the counters that prove what happened.

## Order of operations when the servers come back

1. Copy the folders → log in → Block A (Extras) → Block B (main) → Block C → Block D.
2. Fix anything that fails (send me the evidence as above).
3. Re-test only the failed block.
4. Upload **both** packages — TacoTip 0.8.4 and TacoTip Extras 1.2.3 — in the same session, and write the CurseForge release notes from the README's "What's New in 0.8.4" section (the user-facing bullets), not from the changelog's engineering detail.

## Known and accepted — do not spend test time on these

| Item | Why it is fine |
| :--- | :--- |
| Retail colour band | Held at the shared `1000` by decision. Live totals are unmeasured; the score itself is unchanged. One screenshot later can change the band without touching the score. |
| ruRU Monk / Demon Hunter / Evoker spec names | **Done.** Blizzard's own client strings — Monk Хмелевар / Ткач туманов / Танцующий с ветром, Demon Hunter Истребление / Месть, Evoker Опустошитель / Хранитель / Насыщатель — verified against the client's `ChrSpecialization` DB and the Russian class pages, pinned in `Tests/harness/specname_test.lua`, recorded in the `[0.8.4]` changelog. |
| `/tt lb` on a client where slash order differs | Now forwarded through one resolver in both slash handlers; Era proves it. |
| Classic client socket metrics (Potential GS / Delta / Completion) | Classic has no `GetItemStats`, so those three metrics are unavailable there by design — omitted, never guessed. |
