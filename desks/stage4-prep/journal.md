# stage4-prep — Journal

## 2026-10-18 — Desk opened
- **Purpose:** Bench-only authoring: Stage 4 gear-on-demand implementation-ready brief. No commit, no staging, no code edits.
- **Scope:** One new file only: bench/audits/2026-10-18-stage4-gear-on-demand-brief.md. Read-only on all code, harness, locale, changelog.
- **Context (bench-read):** storage-expansion §6.2 Stage 4 + §5 gear payload + §6.3 budget + §6.4 all-client concerns; stage3-cheap-fields-brief (13-field stride, guild 24-cap, 240-byte door, digest-split, same-transport + answerNoTransport); oracle audit transport findings (same-transport-only, no whisper path ever, counted outcomes); landed wire code TacoTip_Extras/RankSync.lua (WIRE_VERSION, RECORD_FIELDS, version-gated refusal, answerNoTransport, 240-byte door, digest split) reconciled to tree as read.
- **Diet assumption:** Stage-3 stride lands as briefed (version "2" + guild/level/pvp fields); brief states it up front with reconcile-on-dispatch rule.
- **Run:** run_id stage4prep-01, agent_name stage4-prep.
- **Next step:** verify every file:line citation (repo + wow-ui-source five branches), then write brief, then closing entry + signals.

## 2026-10-18 — Done (brief written, citations verified)
- **Worked on:** Wrote bench/audits/2026-10-18-stage4-gear-on-demand-brief.md (request/response G/D same-transport + version-gated, sparse slot=itemID encoding with byte math vs 240 door, extend-digest-split sequencing with of<=4 cap, two-tier cache 32/300 session + 2000-entry persisted gear, shared-bucket throttle + per-sender coalescing + S-before-D priority, five-client API table, 16 harness checks, panel render precedence, 10-item must-not-touch, 8 open questions).
- **Validation:** no code to run; every file:line citation re-grepped before finalizing — 53 repo citations in range, key content lines spot-checked (WIRE_VERSION:165, RECORD_FIELDS:192, answerNoTransport:700-701, GetDebugState:932, ValidateRecord:209, Cache:10, REQUIRED_SLOTS:14, GetCurrent:910, SLOT_ROWS:667, GEAR_NOT_SCANNED:817, lib:CanInspect:3872); wow-ui-source spot-checks (InspectPaperDoll Shared:119, Mainline:136/170/187/244, Item docs 393/909/1025/1483/1673, PlayerScript CanInspect/NotifyInspect, INSPECT_READY literals, ChatInfo 615/803, CooldownBroadcaster 6/8, TBC InspectUI:12). One stale citation fixed (:348 → :399 for LB_TIP_CLICK_GEAR).
- **Current state:** One new bench file + this desk only. No production/harness/locale/changelog file touched; git status shows only pre-existing writer-desk modifications plus this new file and desk.
- **Next step:** Operator/Stage-4 implementer review; re-grep WIRE_VERSION + RECORD_FIELDS on dispatch per §0 reconcile rule.
