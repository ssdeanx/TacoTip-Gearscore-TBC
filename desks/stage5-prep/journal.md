# stage5-prep — Journal

## 2026-10-18 — Desk opened
- **Purpose:** Bench-only authoring: Stage 5+ widgets/visuals implementation-ready brief (everything after gear-on-demand). No commit, no staging, no code edits.
- **Scope:** One new file only: bench/audits/2026-10-18-stage5-plus-widgets-visuals-brief.md. Read-only on all code, harness, locale, changelog.
- **Context (bench-read):** rankbrowser-ux-review (Tier B/C backlog = the "more visuals/widgets" source), stage3-cheap-fields-brief (13-field R;2 stride assumed landed), stage4-gear-on-demand-brief (G/D + two-tier gear cache assumed landed), stage1-and-tier-a oracle audit (same-transport-only, no whisper path, counted outcomes); tier-a-browser / stage3-prep / stage4-prep journals.
- **Run:** run_id stage5prep-01, agent_name stage5-prep.
- **Concurrency note:** writer desks live on code/tests/CHANGELOG; this desk writes one new bench file + own desk only, so no conflict. section3-cheap-fields desk not present in desks/ at read time — Stages 3/4 handled as landed-assumptions with reconcile-on-dispatch regardless.
- **Next step:** verify every file:line citation (repo + wow-ui-source branches), then write brief, then closing entry + signals.

## 2026-10-18 — Done (brief written, citations verified)
- **Worked on:** Wrote bench/audits/2026-10-18-stage5-plus-widgets-visuals-brief.md (12 widgets W1–W12: 6 Tier-B/C carryovers + 6 new; visuals pass for browser/tooltip/gear-panel; per-client table with fresh 5-branch git-show verifications; 17 harness checks; 12 non-goals; slices 5a/5b/5c with gates; 8 open questions).
- **Validation:** no code to run; re-grepped every repo citation before finalizing — 6 drifted cites repaired (class-bar :391→:1057-1061/:479, escape :1183→:1457-1524, search :1201, OnScroll :1332-1334, OnShow :1422, ITEM_DATA_LOAD_RESULT split Core.lua:812,895, showRowTooltip end :400). Fresh wow-ui-source verifications: GetClassAtlas :44 ×5, SearchBoxTemplate ×5, ButtonFrameTemplate ×5 (inheritance differs per family), SOUNDKIT checkbox ×5, GetItemInfo-itemLevel ×5, SetPropagateKeyboardInput era+live, RAID_CLASS_COLORS era+live, CUSTOM_CLASS_COLORS absent (community convention — guard mandatory).
- **Key decisions:** zero wire bytes for the whole stage (no stride/G-D/storage change — byte math inherited, door never re-opened); W12 virtualization gated on realm data (default: do NOT ship); W8 iLvl suffix display-only with numeric-ID call form as open question; no new SV tables (W11 boolean lives in existing settings).
- **Current state:** One new bench file + this desk only. No production/harness/locale/changelog file touched; git status shows only pre-existing writer-desk modifications plus this file and desk.
- **Next step:** Operator/Stage-5 implementer review; re-grep WIRE_VERSION + RECORD_FIELDS + all §1 anchors at dispatch per §0 reconcile rule.
