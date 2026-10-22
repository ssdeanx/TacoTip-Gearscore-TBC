# Session retrospective — TacoTip 0.8.4 / TacoTip Extras 1.2.3 (2026-10-18 → 2026-10-20)

A record of what went wrong, why, and what now prevents it. Read it before your next release; the rules themselves live in `workshop.md`, `hands-up.md` and `CAIRN.md` — this is the story behind them.

## what the session was

Two releases prepared for CurseForge under a hard deadline: TacoTip 0.8.4 (112k downloads, ~10k active per upload) and TacoTip Extras 1.2.3, across five client families, with a publish-once constraint (a ~100 GB download) and no in-game test on four of the five clients. The tree is uncommitted: ~30k lines of work, nothing staged.

Final verified state: main harness **71/71** (lua5.1, lua5.4, luajit), Extras **42/42**, tree-wide luacheck **0/0 in 88 files**, `verify_release --worktree` **PASS** (27 files), `verify_release_extras --worktree` **PASS** (29 files), nothing staged, and the GearScore formula byte-identical to its pre-session state.

## the five failures

they are listed once, in `hands-up.md` -> "problems seen in practice", with
their durable fixes. in short: two lanes edited one file; a wrong brief was
corrected by message instead of replaced; an audit reported an absence it
could not verify and the operator had already proven the feature worked; the
harness agreed with the code instead of the client; and the briefs omitted the
workshop skills, which is what let the first failure stay invisible.

## what worked and should be kept

- **The FrameXML mirror as the only acceptable client source**, with `origin/`-qualified branches and `git -C /home/sam/wow-ui-source show <branch>:<path>`. It settled the slash proxy, the frame visibility, the backdrop API and the portrait zoom — all four of the failures above were only findable there.
- **wago.tools for client strings the mirror cannot carry.** The mirror is English-only FrameXML and its stat tables are engine-side; `wago.tools/db2/<Table>/csv?build=<build>&locale=<locale>` gave the client's own Russian specialization names with `OrderIndex` proving the index alignment. Recipe in `workshop.md`.
- **Revert-to-fail proofs.** A pin that cannot go red on the old code proves nothing. Every change this session carried a mutation proof, and three of them caught their own mistakes (a vacuous comparison, a pin that asserted the wrong default, a mock that could not read an absent field).
- **The `--worktree` mode on both release verifiers**, so the package check validates the tree that ships rather than a commit that does not.
- **The operator's in-game observations as a test oracle.** The portrait zoom, the transparent gear panel, the unclickable button, the duplicated slash commands and the tooltip's overlapping text were all found by a human looking at the game, not by a suite.
- **The bench as the shared workspace.** 26 audit artifacts; findings, dispositions and verdicts are files another desk can read rather than messages in a transcript.

## what this audit changed

- **19 signal files renamed** to the `<timestamp>.json` convention `hands-up.md` documents — the dashboard orders by it, and `done.json` / `checkpoint.json` / `hunter2.json` broke that ordering. All signal filenames now conform.
- **`CAIRN.md`'s precedence rung 3 cited `AGENTS.md`, which does not exist in the tree** (only its export-ignore survives). The rung now points at the standing documents that do exist.
- **Two desks carry no signal** (`fix-main-slash-proxy`, `setup`): a desk that never signalled is invisible to the dashboard. Both wrote journals; a `done` signal would have made them findable.

## what a future session can rely on

    bash Tests/harness/run_all.sh              # 71/71 × 3 interpreters
    bash TacoTip_Extras/Tests/harness/run_all.sh  # 42/42 × 3 interpreters
    luacheck .                                  # 0/0 in 88 files
    bash Tools/verify_release.sh --worktree          # 27 files, TacoTip 0.8.4
    bash Tools/verify_release_extras.sh --worktree   # 29 files, Extras 1.2.3

The client facts are in `workshop.md`; the failure modes and their signals are in `hands-up.md`; the evidence labels and the precedence ladder are in `CAIRN.md`. Read all three before the first brief of the next release.

## open items

- Retail GearScore colour band — held at the shared `1000` by operator decision; one live screenshot decides it.
- `/tt lb` and `/ttgsdebug` — implemented and pinned; the only two things an in-game pass can still prove.
- The `H2` inspect tri-state contract, and the Demo Hunter third specialization the client DB now carries (`Пожиратель`), which the add-on's two-entry table does not model.
