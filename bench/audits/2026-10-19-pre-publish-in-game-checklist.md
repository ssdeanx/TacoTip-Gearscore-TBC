# Pre-publish in-game checklist — TacoTip 0.8.4 + TacoTip Extras 1.2.3

Everything the offline harness **cannot** prove, in one ordered pass. Run this on each client you test, then publish.

The harness already covers (do NOT re-verify): scoring values and bands, per-client detection, the wire format, the browser/panel rendering, the taint guards, every failure counter, and the locale parity. **64/64 main, 42/42 Extras, lint 0/0** — if a behavior below contradicts this list, it is a regression, not a surprise.

---

## A. Every client (11509 Era · 20506 TBC · 38002 Titanforge · 16001 Forever · 120105 Retail)

Run in this order — each step depends on the one before it.

1. **Load the game with both addons.** No Lua errors on load. `/tacotip diag` opens and prints its sections.
2. **Hover a friendly player.** The tooltip shows GearScore + iLvl; the **name line is the class colour**; the spec line is present and correct; the **border is the class colour**. Open the character panel → the GearScore and iLvl values match the tooltip and are **12px** (readable, not clipped).
3. **Hover an enemy player.** The tooltip resolves to *that* player — **not** to your mouseover target's class colour. Then hover a **hostile NPC**: the border stays the base colour (players get class colour, NPCs do not — by design).
4. **Open the character panel, then close it and re-open it.** The overlay shows your real score, **never a standing `0`**. Do the same with an inspected player (right-click → Inspect): the inspect pane shows their GearScore/iLvl, never `0`.
5. **Open the Game Menu and quit.** No `ADDON_ACTION_FORBIDDEN`, no error spam. This is the taint fix — it must be clean.
6. **Toggle "Instant fade" in the Tooltips options.** On Retail/Forever it takes effect. **On Era/TBC/Titanforge the checkbox must be disabled with an explanation** (those clients have no `GameTooltip.FadeOut`) and `/tacotip diag` must name the mode.
7. **Toggle "Scan nearby players" off, then on.** The checkbox reflects what the engine is really doing; a toggle that does not take prints one chat line and appears under PROBLEMS. Hover and target inspection keep working either way.
8. **Open the settings menu, then the TacoTip options page.** The panel opens **above** the Settings canvas. Open the leaderboard (`/tt lb` or `/tt ranks`) — it opens **above** the Settings menu too. Click a row → the gear panel opens **above** the browser, with a **readable opaque background**, real item links, and slot labels in the **client's own language**.
9. **A player you have no gear for** → the gear panel says the data is unavailable and points at **Scan now** — never a blank panel, never `item:0`. Press Scan now, and confirm the panel fills in.
10. **Compare a ~1400 GS player.** The tooltip colour and the leaderboard row colour must be **the same band** (Era = the 200-domain bracket: 1400 reads Artifact red, not the old purple).

## B. Era / TBC / Titanforge specifically

11. **Walk away from a player until they leave interact range.** **No "Not in Range" popup, and no repeating error.** The inspect range gate (20–21 yards on Era) is frozen — this is the 0.8.3 fix and it must not regress.
12. **Inspect a player who has no guild** → the inspect frame renders fully (never blank). Inspect a player who **does** have a guild → the guild line shows, and it does not erase another addon's tooltip line (Baganator's tracked item amount survives a hover).
13. **Talent points**: hover a player and confirm the talent line shows real points, not icon IDs.

## C. Retail specifically — POST-PUBLISH ONLY (see the rule above)

These are **not** pre-publish gates; they are the field spot-checks for the behaviors that ship on offline proof. Run them after the upload if you want to catch a Retail-specific surprise early, but do not hold the release for them.

14. **Right-click a player → Inspect.** The inspect frame opens without a crash, the gear is present, and the paper doll is not stripped.
15. **Hover an item you have not hovered before** → its iLvl / GearScore arrive within ~1s (the cold-path item request that was silently dead on Retail is fixed).
16. **Character frame GearScore colour.** Endgame Retail is **held at the shared 1000 bracket**, so a high-iLvl character may read constant Artifact — **take one screenshot and judge it**. This is the open decision; the band mapping can be changed later without touching the score.
17. **Spec icons** on unit tooltips render (the modern path uses a Texture, not a `|T` escape).

## D. Extras only

18. **Sync**: with another client nearby, `/tt lb` shows fresh rows. The wire is `R;2` — a mixed-version client on the same realm must not corrupt rows.
19. **A guild filter and the LEVEL column** work in the browser; the `#` rank invariant holds after sorting.
20. **Pawn**: with Pawn installed but enabled mid-session, the option becomes available immediately and the scores appear after the next reload; `/tacotip diag` says which state you are in.

## E. Added by the final gates (2026-10-19)

These came out of the last four review passes and are **not** provable offline.

21. **`/tt lb` must open the LEADERBOARD, not the TacoTip options panel.** The main add-on registers `/tt` and Extras registers `/tt lb`; the client walks slash commands and takes the first prefix match, and that order is **not specified** — so this one is **NOT offline-provable** and is the single highest-risk item in this release. The unambiguous aliases `/ttrank`, `/ttranks`, `/ttleaderboard`, `/ttgs`, `/ttgsdebug` and the minimap button are unaffected — use them if `/tt lb` misbehaves, and report it so it can be fixed in a follow-up release.
22. **Potential GS / Delta / Completion on Retail.** Two separate defects were fixed at once (the level-70 policy was hard-wired at the scoring source, and the socket-capacity prefix never matched the client's `EMPTY_SOCKET1/2/3` keys). On Retail and WoW Forever these three metrics should now produce **numbers** where they previously said "Unavailable". Confirm a real character shows numbers, and that the values look sane next to a known-good character. On the three Classic clients there is no `GetItemStats`, so the socket path stays absent there — that degradation is documented and expected.
23. **`/ttgsdebug` must actually print the counters.** The Extras' diagnostic counters (driver renders/rows, rank-record errors, row-tooltip errors, score-colour fallbacks, initialize failures) were previously reachable only from the test harness. Confirm the command prints them.
24. **The Extras tooltip surface must not wedge.** If the Extras rows stop appearing on a tooltip, a `/reload` used to be the only cure; the render path is now wrapped so a failure is counted and the surface recovers. If rows ever stop appearing, run `/ttgsdebug` and capture the output before reloading.
25. **The leaderboard footer must show real numbers in your language.** Ten non-English Extras locales had their format specifiers stripped, so the footer rendered the player's own standing as a literal `#d` and the sort readout as `s s`. Check the footer and the sort label on a non-English client if you have one (or check that they are at least not literal `d` / `s`).
26. **Upgrade path**: if you had Extras installed before 0.8.4, install 0.8.4 + Extras 1.2.3 over it and confirm the Extras tooltip surface still works and that TacoTip's own player GearScore is still enabled. A stale recovery journal used to latch the Extras off permanently after a TacoTip upgrade; it now restores the setting and re-acquires.

## Retail / WoW Forever — NOT in-game tested before publish

**Rule: nothing is published until the work is complete, and publishing is a one-shot ~100 GB download.** So Retail and WoW Forever do **not** get an in-game pass before upload — they ship on **offline proof**: a harness pin that drives the branch, plus FrameXML evidence for the client-side behavior it depends on (`git -C /home/sam/wow-ui-source show/grep`, branch-qualified).

Everything below is therefore a **post-publish spot check**, not a pre-publish gate. If one of these turns out wrong in the field, it is a follow-up release — not a reason to hold this one.

| Behavior | Offline proof | Post-publish check |
| :--- | :--- | :--- |
| Right-click → Inspect opens without crashing, including a player with **no guild** | the guild-guard wrapper is installed only when `Blizzard_InspectUI` finishes loading (that Blizzard addon is `## LoadOnDemand: 1` on live/forever — the global does not exist at our load time), and the harness drives the wrapper with a raising `InspectGuildFrame_Update` and asserts the error does **not** escape | Inspect any player on Retail |
| Uncached item data arrives (the cold-path item request was dead on Retail) | namespace-first resolution of `C_Item.GetItemInfoInstant` (the bare global exists only as a deprecated alias on the three Classic branches — `Blizzard_DeprecatedItemScript/Deprecated_ItemScript.lua:10` — and that file is absent on live/forever), pinned to one request carrying a numeric item id | Hover a never-hovered item |
| Potential GS / Delta / Completion produce numbers | the level-70 policy is plumbed to the scoring source and pinned both ways; the socket count now comes from the **documented** `C_Item.GetItemNumSockets` API (the same call Blizzard's own `PaperDollFrame.lua:2775` makes — the item link *is* the argument), and the cross-check rejects a count that contradicts the item's gem list in **either** direction (a contradicting item renders unavailable, never a number) | Look at your own tooltip — and compare one item with a **known** empty socket: if Potential GS looks off, the socket count is the first suspect |
| Instant fade | `GameTooltip.FadeOut` exists only on live/forever (`Blizzard_GameTooltip/Mainline/GameTooltip.lua:1017`); the capability probe records the mode and the harness drives all three modes | Toggle it |
| Character/inspect pane refresh | `CharacterFrame` and `InspectFrame` carry `hidden="true"` on all five branches, so their `OnShow` fires; the dead `PaperDollFrame` hooks are gone; pinned | Open/close the pane |
| Leaderboard layering | `GameMenuFrame` = `toplevel="true" frameStrata="DIALOG"` and `SettingsPanel` = `toplevel="true" frameStrata="HIGH"` on **all five** branches, so `FULLSCREEN_DIALOG` + toplevel sits above both | Open the browser over Settings |
| Gear-panel slot labels | the client's `INVTYPE_*` globals exist on all five branches (`INVTYPE_HANDS` exists on **none** — that was the bug); all 17 names are pinned | Open a gear panel |
| Era grading | adapter-first per-client bracket: Era 1400 = Artifact red (200 domain), TBC 1400 = Superior blue (400 domain) | Compare tooltip and row |
| `/tt lb` slash routing | the client walks slash commands and takes the first prefix match, and that order is **not** specified — so this is NOT offline-provable | Type `/tt lb` |
| Retail colour band | the bracket is **held at the shared 1000** by decision; live totals are unmeasured | One screenshot |

---

## Known open — decided, not blocking

| Item | Decision | Why it is not a blocker |
| :--- | :--- | :--- |
| Retail GearScore colour band | **held at the shared `1000`** | Status quo before the 0.8.4 work; the score itself is unchanged. One screenshot decides it (step 16). |
| HunterScore line colour | **intentionally the GearScore band** | Operator ruling: it reads as the hunter's counterpart to the iLvl line. |
| Gear-panel slot labels | **the client's own `INVTYPE_*` strings** | Operator ruling: "get the label from wherever you can". They ship translated in every language the game ships; all 17 names are now pinned so a typo cannot ship again. |
| ruRU Monk / Demon Hunter / Evoker spec names | **still German/English placeholders** | Needs a translator. No Russian strings were invented. |
| Extras release status | the CurseForge listing exists and serves **1.2.2** | 1.2.3 ships alongside 0.8.4 — upload it as part of this release, or the READMEs' "published alongside" wording is wrong. |
| Extras privacy wording | now documented in the Extras README | The character ID is on the wire, records of players *you inspect* are broadcast too, and the channel name + message format are in the shipped source. Nothing to do — it is disclosed. |

## Known open — needs a decision from you

- **The gear panel's empty-state wording** — "not scanned yet" vs "unavailable right now" is chosen by *session* state, so a relog can change the message for the same player. Both are accurate per session; the operator flagged "unavailable now" as the preferred wording, but the change was reverted when it became clear the report was about the panel's missing background rather than its text. One word from you settles it.
- **H2 tri-state** — the inspect queue's `DoInspect` still returns "true" for a queued unit and the caller discards it. Behaviour is correct today; the contract is not yet written down.
- **`/tt lb`** — if step 21 shows the slash conflict is real, rename the Extras commands to non-prefix forms (`/ttlb`) or have the main add-on's `/tt` forward `lb`/`rank`/`ranks`/`leaderboard`.


## Never auto-fixable — do not "correct" these

- The raw global replacement of `InspectGuildFrame_Update` (`main.lua`) stays: it swallows a Blizzard crash that otherwise blanks the inspect frame, and `hooksecurefunc` cannot swallow an error. Its only callers are plain FrameXML scripts on Retail/Forever; the Classic family has no such global.
- `CanInspect` is called with **one argument everywhere**. The second argument is `showError`, not a range flag — passing it makes the engine display the very message 0.8.3 removed.
- The Classic inspect range gate (20–21 yards) is frozen. A regression there is the failure 0.8.3 exists to prevent.
