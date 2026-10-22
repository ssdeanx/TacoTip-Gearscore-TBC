# fix-main-slash-proxy — Journal

## 2026-10-20 — Desk opened
- **Purpose:** the BLOCKING fix — the main add-on's `/tt` handler never forwards
  to TacoTip Extras in the real client, because the client's `SlashCmdList` is a
  PROXY table whose real contents are WIPED before dispatch. The shipped
  changelog and the code comment both state the WRONG mechanism ("first matching
  prefix, scan order not specified"). This desk corrects the resolver, the
  stated mechanism, and the harness fidelity (the MAIN harness models
  `SlashCmdList` as a plain, never-proxied, never-wiped table, so the pin
  cannot fail for the real reason today).
- **Scope:** the MAIN add-on only — `gearscore.lua`, `options.lua`, `main.lua`,
  `Locale/*.lua`, `README.md`, `CHANGELOG.md`, `Tests/harness/*`. Plus the
  main-side cleanups from the final maintainability audit (H1 border default,
  S3 dead positional locale entries, H5 frame-mock fidelity, S9 README slash
  list, S10 cross-add-on setting mapping comment).
- **Out of scope / frozen:** `TacoTip_Extras/**` (read-only), the Classic Era
  inspect range gate, the raw GearScore formula, the Retail 1000 bracket, any
  two-argument `CanInspect`, `*.toc` / version changes, `bench/` writes, other
  desks.
- **No commit, no staging.**
- **Next step:** read the four desks named in the brief (`fix-main-slash-forwarding`
  plus the final review desks) for the audit findings, verify the client
  mechanism against the FrameXML mirror, then implement.

### Baseline (VERIFIED, 2026-10-20, before any edit)
- `bash Tests/harness/run_all.sh` → **71 invocations: 71 passed, 0 failed** on
  **lua5.1, lua5.4 and luajit**.
- `luacheck .` → **0 warnings / 0 errors in 88 files**.
- `bash Tools/verify_release.sh` → **PASS**.
- `bash TacoTip_Extras/Tests/harness/run_all.sh` → **42 invocations: 42 passed,
  0 failed**.

---

## Note from `fix-extras-debug-global` (Extras side, 2026-10-20)

- The Extras' `/ttgsdebug` snapshot is now published on the plain global
  **`_G.TacoTipExtrasPrintDebugSnapshot`** (`TacoTip_Extras/Core.lua:1161-1171`,
  written inside `registerDebugCommand`, the same place the slash handler is
  registered). It is the **same function object** the `/ttgsdebug` entry
  invokes, so a `/tt` forwarding path can call it directly instead of reading
  the client's wiped `SlashCmdList`. The Extras' own `/ttgsdebug` is unchanged
  and still works.
- That name is the contract for the main lane's call site. Nothing in the main
  add-on was touched by that desk.
