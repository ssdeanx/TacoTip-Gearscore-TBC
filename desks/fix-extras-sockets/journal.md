# fix-extras-sockets — Journal

## 2026-10-20 — Desk opened
- **Purpose:** close the last open correctness item on **TacoTip Extras v1.2.3**:
  the socket capacity, which published an overstated Potential GS / Delta /
  Completion on Retail and WoW Forever because it was read from a stat-table
  key the FrameXML mirror cannot confirm. Publish-bound: the number changes a
  PUBLISHED number on two clients and cannot be in-game tested before publish,
  so its source has to be a DOCUMENTED, mirror-verified API.
- **Scope:** `TacoTip_Extras/Scanner.lua`, `TacoTip_Extras/Scoring.lua`,
  `TacoTip_Extras/Tests/harness/*` (Extras only),
  `TacoTip_Extras/CHANGELOG.md`, `TacoTip_Extras/README.md`, plus the one
  shared contract file the Extras harness loads
  (`Tests/harness/mock_contract.lua`). **NOT** the main add-on, **NOT**
  `Locale/`, **NOT** any `*.toc` or version string, **NOT** `bench/`, **NOT**
  any other desk. No commit, no staging.
- **Baseline measured (not assumed):** `bash TacoTip_Extras/Tests/harness/run_all.sh`
  → `TOTAL 42 invocations: 42 passed, 0 failed`; `cd TacoTip_Extras && luacheck .`
  → `Total: 0 warnings / 0 errors in 26 files`; `bash Tools/verify_release_extras.sh`
  → `verify_release_extras: PASS`; `bash Tests/harness/run_all.sh` → `TOTAL 70
  invocations: 70 passed, 0 failed`.
- **Next step:** the operator's in-game eyes on a Retail and a WoW Forever
  character (the pre-publish checklist item 22) — the capacity now comes from
  the client's own item data, so a wrong answer would show up there as a
  contradiction, not as a number.

## 2026-10-20 — Mirror evidence, the decision rule, and the fix
- **Mirror evidence (read-only, `/home/sam/wow-ui-source`).** The socket-count
  API is `C_Item.GetItemNumSockets(itemInfo)`, documented at
  `Interface/AddOns/Blizzard_APIDocumentationGenerated/ItemDocumentation.lua`
  **`:854` on `origin/live`**, **`:876` on `origin/forever`**, **`:586` on
  `origin/classic_era`** (and the same `:586` on `origin/classic_anniversary`
  and `origin/classic_titan`). Its entry is one `itemInfo` argument and one
  `socketCount` return, both non-nilable.
  The generated docs name the argument `itemInfo` — an opaque item handle —
  and do **not** say how to build one from a link. **Blizzard's own code
  answers that**: `Interface/AddOns/Blizzard_UIPanels_Game/Mainline/PaperDollFrame.lua`
  **`:1728`** does `self.SocketDisplay:SetItem(GetInventoryItemLink("player", self:GetID()))`,
  **`:2766`** defines `PaperDollItemSocketDisplayMixin:SetItem(item)`, and
  **`:2775`** does `local numSockets = C_Item.GetItemNumSockets(item);` — so
  `item` **is** the raw link string, passed straight into the API. The link is
  therefore the `itemInfo` argument, and the add-on already holds it
  (`nativeLink`). The sibling `C_Item.GetItemGemID(itemInfo, index)`
  (`ItemDocumentation.lua:512` live, `:534` forever, `:321` classic_era) is
  indexed from **one** over the socket positions —
  `PaperDollFrame.lua:2777-2780` loops `for index, slot in ipairs(self.Slots)`
  and reads `C_Item.GetItemGemID(item, index)`.
- **Decision rule — branch taken: STEP 2 (the documented API is drivable
  offline).** The rule's test is whether the `itemInfo` argument can be
  established from the mirror; it can, because Blizzard's own call site passes
  the raw item link and the add-on already has that string. So the capacity
  is now read from `C_Item.GetItemNumSockets(nativeLink)` and the published
  number is **not** derived from the unconfirmable stat table. Step 4 (revert
  to an unavailable metric) did **not** apply.
- **Per-item changes:**
  1. `Scanner.lua:32-89` — the `EMPTY_SOCKET*` header block is replaced by the
     evidence block: what the stat table could not be trusted for, the
     documented API and its line references, Blizzard's call shape, and the
     unchanged scope gate.
  2. `Scanner.lua:19` — `SOCKET_POSITIONS` is taken from
     `Scoring.SOCKET_POSITIONS` (one source of truth for the bound).
  3. `Scanner.lua:514-552` — `readSocketCapacity` reads
     `C_Item.GetItemNumSockets(nativeLink)` under `pcall`, with the
     `GetItemStats` **scope gate unchanged** above it; a missing API, a raise
     or a non-integer answer is withheld (`socket-capacity-unavailable` /
     `socket-capacity-invalid`).
  4. `Scanner.lua:554-568` — `buildSocketCell` withholds a capacity above the
     link's three gem positions (`socket-capacity-exceeds-gem-list`).
  5. `Scoring.lua:98-105` — `SOCKET_POSITIONS = 3` (the parser reads exactly
     three gem fields) and exported for the Scanner.
  6. `Scoring.lua:538-600` — `readSocketEvidence` now reconciles the capacity
     against the item's parsed gem list in **BOTH** directions: too small
     (`socket-gem-mismatch-N`) and too large
     (`socket-capacity-exceeds-gem-list`), plus the position-by-position gem
     agreement over the positions the link actually has.
  7. `Tests/harness/load_test.lua:1029-1046` — the mock's `GetItemStats` no
     longer publishes the fixed `EMPTY_SOCKET1..3` triple; that fiction went
     with the code that read it.
  8. `Tests/harness/load_test.lua:1141-1163` — `ITEM_SOCKETS` /
     `registerSocketCount`: the client's item database, keyed by item ID,
     because the socket count is a property of the ITEM.
  9. `Tests/harness/load_test.lua:1327-1337` — the mock publishes
     `C_Item.GetItemNumSockets` on **every** client, so the Classic
     degradation is proved to be the **gate's** doing and not an accident of
     the model.
  10. `Tests/harness/load_test.lua:1361` — the Harness Helm is a **two**-socket
     item, so the old fixed triple (three) and the API's answer disagree and
     the source pin can tell them apart.
  11. `Tests/harness/load_test.lua:2700-2890` — the socket block: the scanner
     reads the capacity from the API; the Classic/nostats degradation is
     unchanged; a one-socket item and a sockless item are scanned **end to
     end** and must publish zero empty sockets.
  12. `Tests/harness/load_test.lua:3320-3435` — the `Scoring.Evaluate` pins: a
     reconciling item against the hand-derived truth, and a capacity that
     contradicts the gem list in **either** direction.
  13. `Tests/harness/mock_contract.lua:192-227` — the contract entry for
     `C_Item.GetItemNumSockets` (one value, as the client publishes one),
     with the branch-qualified citation; asserted by the Extras harness.
  14. `TacoTip_Extras/CHANGELOG.md` — the `[1.2.3]` socket bullet replaced
     (no version bump; earlier sections untouched), and the section's
     "Verified" paragraph re-pointed at the new pins and the new check counts.
  15. `TacoTip_Extras/README.md` — the socket bullet and the `GetItemStats`
     bullet rewritten, and the client table's last column renamed to say what
     it gates.
- **Revert matrix (each probe: apply → capture the red → restore → capture the
  green; the restore is verified by sha256).** Script:
  `/tmp/opencode/socket-revert-matrix.py`, transcript:
  `/tmp/opencode/socket-revert-matrix.txt`.
  1. the capacity SOURCE put back on the stat-table sum (with the old mock
     triple) → 5 red on Retail: the scanner's capacity read (3, expected 2),
     the one-socket capacity (3, expected 1), the one-socket empty count (2,
     expected 0), the sockless capacity (3, expected 0) and the sockless empty
     count (3, expected 0). **Classic Era stayed GREEN** — the Classic
     clients' published behaviour is unchanged by the source. (Under the old
     code a one-socket item published TWO empty sockets and a sockless item
     THREE, where the truth is zero and zero.)
  2. the cross-check's **too-large** branch removed → 5 red: the capacity-4
     item published Potential GS 340, Delta 25, a Completion table and an
     empty-socket count of 2 instead of withholding them.
  3. the cross-check's **too-small** branch removed → 5 red: the capacity-1
     item published Potential GS 335, Delta 15, a Completion table and an
     empty-socket count of 0 instead of withholding them.
  4. the socket accounting counting every socket as filled → 5 red: the
     reconciling item published 330 / 15 / filled 2 / percent 67 against the
     hand-derived 335 / 20 / filled 1 / percent 33, and the empty count read 0
     instead of 1.
  5. the **scope gate** removed → 1 red on Classic Era: "without GetItemStats
     the socket path stays absent (the documented degradation)" — the socket
     cell came back `complete`. That is the proof that the Classic degradation
     is the gate's doing.
  Every arm was restored to `0 failed` after its probe.
- **Validation on the restored tree:** `bash TacoTip_Extras/Tests/harness/run_all.sh`
  → **42 invocations: 42 passed, 0 failed** on lua5.1 / lua5.4 / luajit;
  `cd TacoTip_Extras && luacheck .` → **0 warnings / 0 errors in 26 files**;
  `bash Tools/verify_release_extras.sh` → **PASS**; `bash Tests/harness/run_all.sh`
  → **70 invocations: 70 passed, 0 failed**. Per-client check counts:
  496 on Classic Era / TBC / Titanforge, 528 on WoW Forever / Retail.
- **What is NOT claimed.** The mirror confirms the API's presence, its
  argument shape and its return shape; it does not say what a live client
  returns for an item whose template data is not loaded, so the read is
  `pcall`-guarded and a failed or non-integer answer is withheld rather than
  guessed. `GetItemGemID`'s per-socket semantics for an **equipped** link are
  **not** confirmed from the mirror, which is why they are not used to publish
  a number — the link stays the cross-check.
- **Known leftover, deliberately out of scope:** `TacoTip_Extras/Options.lua:274`
  still maps the now-dead reason `socket-order-unverified-above-three` to a
  label, and the new reason `socket-capacity-exceeds-gem-list` has no label.
  `Options.lua` is outside this lane's scope; the panel already shows the raw
  reason code for the socket contradiction reasons (`socket-gem-mismatch-N`
  never had a label either), so nothing is mis-rendered — but the dead entry
  should be pruned by whoever owns that file.
- **Next step:** the operator's in-game check on a Retail and a WoW Forever
  character (pre-publish checklist item 22): a real item's empty-socket count
  should equal the number of empty sockets the tooltip shows, and Potential GS
  / Delta / Completion should read numbers rather than "Unavailable".

## 2026-10-20 — [signal:done] The socket capacity now comes from the documented API; the cross-check runs both ways
- The capacity is read from `C_Item.GetItemNumSockets(itemLink)` — documented
  at `ItemDocumentation.lua:854` (live) / `:876` (forever) / `:586` (classic),
  and called by Blizzard with the raw item link at
  `PaperDollFrame.lua:1728` → `:2775`. The unconfirmable stat-table sum is
  gone.
- The cross-check against the item's parsed gem list is **bidirectional**: too
  small and too large are both contradictions, and a contradicting count
  renders the socket-based metrics **unavailable, never a number**.
- The `GetItemStats` **scope gate is unchanged**, so Classic Era, TBC
  Anniversary and Titanforge keep their shipped degradation; the harness models
  `GetItemNumSockets` on all five clients so the degradation is proved to be
  the gate's doing, and the gate-removal probe turns that pin red.
- Five revert probes, each red then restored green; 42/42 on lua5.1/5.4/luajit,
  luacheck 0/0 in 26 files, the release verifier PASS, the main harness 70/70.
- Desk path: `desks/fix-extras-sockets/`. Signal:
  `.signals/2026-10-20T00-00-00Z-done.json`.
