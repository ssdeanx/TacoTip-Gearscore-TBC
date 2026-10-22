# stage3-prep — Journal

## 2026-10-18 — Desk opened
- **Purpose:** Bench-only authoring: Stage 3 cheap-fields implementation brief + five-client in-game test checklist. No commit, no staging, no code edits.
- **Scope:** Two new files only: bench/audits/2026-10-18-stage3-cheap-fields-brief.md + bench/audits/2026-10-18-five-client-test-checklist.md. Read-only on all code, harness, locale, changelog.
- **Context (bench-read):** storage-expansion §6.2 Stage 3 + §4 cheap fields + §6.3 budget + §6.4 all-client concerns; oracle audit in-game-only checklist + findings; desks section1-delivery / section2-storage / tier-a-browser journals; wire-diet desk intent (diet stride not yet landed at read time).
- **Diet assumption:** wire-diet target shape (version,guid,name,classID,gs,ilvl,timestamp,specID) assumed landed; brief states it up front with reconcile-on-dispatch note.
- **Next step:** verify every file:line citation (repo + wow-ui-source five branches), then write both files, then closing entry + signals.

## 2026-10-18 — Done (both files written, citations verified)
- **Worked on:** Wrote bench/audits/2026-10-18-stage3-cheap-fields-brief.md (13-field R;<ver> stride on the LANDED diet WIRE_VERSION="1"/RECORD_FIELDS=9, byte math vs 240 door, guild 24-cap rule, per-field scan capture, browser/storage/harness/§4-boundary, 8 open questions) + bench/audits/2026-10-18-five-client-test-checklist.md (cold-login→guild→party/raid→instance→channel→browser→debug, SOLO/2+ marked, blank per-client columns).
- **Mid-task drift handled:** wire-diet desk landed (stride 11→9 with version gate + versionReject) and the whisper-drop landed (answerNoTransport counted, _sender) while drafting — both files reconciled to the landed code; every repo citation re-grepped to post-landing line numbers; mechanical sweep: 68 file:line citations, 0 out-of-range.
- **Current state:** Both files on the bench, uncommitted. No production/harness/locale/changelog file touched; only the two new bench files + this desk.
- **Next step:** Operator/implementer review; Stage 3 implementer re-greps WIRE_VERSION + RECORD_FIELDS on dispatch per the brief's reconcile rule.
