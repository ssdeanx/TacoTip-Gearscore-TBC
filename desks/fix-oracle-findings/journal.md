# fix-oracle-findings — Journal

## 2026-10-18 — Desk opened
- **Purpose:** Clear accumulated open Oracle findings — coverage gaps and nits only, no behavior changes except one bounded sanitizeID validator fix.
- **Scope:** Tests/harness/load_test.lua, Tests/harness/rankbrowser_test.lua, RankBrowser.lua (comments only), RankDB.lua (sanitizeID only), CHANGELOG.md (ref fixes only). NOT RankSync.lua, Scanner.lua, Core.lua, Locale/, bench/, other desks.
- **Next step:** bench-read section1/2b/3/4 journals + both Oracle audits, then baseline suite, then implement items A/B/C.

## 2026-10-18 — [signal:checkpoint] pins landed, suite green
- **Worked on:** all Oracle carry-forward items. A: 21 new pins in runQueryProtocol (inner closure runStage1Coverage, own local budget): RAID answer (2), INSTANCE_CHAT answer (2) + broadcast (1), CHANNEL-active answer (2), fireEvent CHAT_MSG_ADDON e2e (2), legacy-global sendNoInfo (2), oversize (2), sendOther (1), sendError (2), sendChannelThrottle (2), /ttgsdebug print lines (2), 6-hex outbound id (1). B: diet refusal labels reworded as group pins + comment states the pre-diet isolation matrix; junk-realm-key arm (2, placed before the Aggro4 GetRecord resurrection the existing comment names); heap GUID-tiebreak arm (2, discrimination verified by standalone heap sim on all 3 interpreters: no-tiebreak pops 02819/12690/11616, never 00000); specID capped at 9999 in sanitizeID (bound 5 bytes off validator-max R standalone: 269->264, single-S 280->275, still refused by the 240 door; typical rows unchanged); 6 stale file:line refs fixed by grep (RankDB 125->233, 219->444, 393->638; RankBrowser 104->192; Scanner 173->266; RankSync 897->1335); scan-complete comment fixed (later lanes moved it 559-560/497-498 -> 627-628 but never fixed the stale locale claim). C: Tier-A count 136 -> 163-at-revision; Stage-2 34->39 (+junk/tiebreak/bound enumerated); suite 334/345 -> 403/414; Stage-3 twelve->28 (7+21); Stage-4 seventeen->39 (24+9+6).
- **Validation:** run_all.sh TOTAL 42/42 (lua5.1/5.4/luajit); LINT=1 0/0; era load 403, retail/forever 414, rankbrowser 163, 0 failed (quoted from runs).
- **Scope kept:** production = sanitizeID bound + one comment only; no RankSync/Scanner/Core/Locale/bench edits; no commit/staging.
- **Next step:** final journal + done signal.
