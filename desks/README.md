# desks

one desk per workstream. the desk is the memory: its `journal.md` carries state
across sessions, its `.signals/` carries structured output.

## sitting at a desk

1. read `CAIRN.md` first.
2. read the desk's `journal.md` — newest entry at the top.
3. work; before the session ends, write the journal entry — even a session that
   produced only a dead end.

## opening a desk

short kebab-case name. if `desks/<name>/journal.md` exists the desk is live — do
not overwrite it; resume it. a desk is created, never overwritten.

## rules

- a desk is a peer, not a sub-agent — equal standing to disagree.
- one desk, one focus; too broad a scope is two desks.
- another desk's files are not yours — leave a note in *their* journal.

## current desks

- `quit-taint-fix` — the Classic Era exit-game refusal: the vendored library replaced the client's global `PlaySound`, which the game menu's own Logout/Quit callback calls two lines above the protected `Logout()` — fixed, plus the whole `securecall` containment class, the publish-gate verification and the Extras' dead equipment summaries.
- `taint-client-source-2026-10-21` — the client-source coupling between the game menu and the shared GameTooltip.
- `taint-crossclient-2026-10-21` — the cross-client taint-surface sweep: which blizzard globals the tree replaces and whether any of them collides with the game menu's path.
- `main-publish-sweep-2026-10-21` — the main add-on's publish sweep: the frozen invariants, the hook sites that can raise per client, locale parity and packaging.
- `extras-publish-review-2026-10-21` — the TacoTip Extras' publish review, which found the dead equipment summaries and the mock that hid them.
- `setup` — the workshop setup and coordination workstream.
- `fix-main-slash-forwarding` — the main add-on's `/tt` handler now forwards the TacoTip Extras' leaderboard sub-commands (`/tt lb` and friends) to the Extras instead of opening the options panel.
- `fix-extras-final-review` — the TacoTip Extras side of the final release review: the leaderboard toggle published on a plain global (`_G.TacoTipExtrasToggleLeaderboard`), "Comfortable rows" localized in all eleven locales, the `1.2.3` summary row extended and the gear-panel backdrop claim corrected, and the unreachable multi-word slash aliases documented.
- `fix-extras-silent-failures` — the TacoTip Extras side of the final silent-failure audit (2 MEDIUM + 7 LOW): the gear panel is closed with the browser and re-rendered after a rebuild, a raising scorer is counted and reported instead of leaving the old verdict in place, the footer's two buttons no longer overlap, the mode dropdown and two leaderboard strings are localized, the options hit rects are re-measured on refresh, two buttons say when a module is missing, a missing rank database says so, and unticking every tooltip field no longer loses the tooltip mode.
- `fix-extras-maintainability` — the TacoTip Extras side of the final maintainability audit (5 HIGH + 9 MEDIUM + 7 LOW across both add-ons): the ▲ glyph is right in all eleven locales, 38 dead locale keys are gone and the README's localization claim is now honest, the gear panel's escape comment matches the code, the class-colour chain lives in one place, the gear panel's geometry is named, the two identical defaults functions are one, and the harness models the client's template title.
