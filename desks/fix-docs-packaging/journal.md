# Fix Docs & Packaging — Journal

## 2026-10-19 — Desk opened
- **Purpose:** documentation truth + release packaging for the publish-bound
  TacoTip 0.8.4 / TacoTip Extras 1.2.3 pair.
- **Scope:** `README.md`, `CHANGELOG.md`, `THIRD_PARTY_NOTICES.md`,
  `TacoTip_Extras/CHANGELOG.md`, `TacoTip_Extras/THIRD_PARTY_NOTICES.md`,
  `.gitattributes`, `Tools/verify_release.sh`, new
  `TacoTip_Extras/.gitattributes` and new `Tools/verify_release_extras.sh`.
  **Not** `TacoTip_Extras/*.lua` production code, **not**
  `TacoTip_Extras/README.md` — another lane owns those.
- **Next step:** hand the Extras README corrections to the owning lane (exact
  text below), then commit.

---

## 2026-10-19 — Documentation truth and packaging, seven items
- **Worked on:** the shipped README contradicted the shipped notices on library
  licences (README asserted MIT for `CallbackHandler-1.0`, `LibDetours-1.0` and
  `LibForeverInspector`; the notices had **withdrawn** all three as
  unverifiable and recorded them `UNKNOWN`). The README table is now the
  notices' table verbatim; the "permissive and MIT-compatible" sentence is
  gone; `THIRD_PARTY_NOTICES.md` is named as the single source of truth. No
  claim invented in either direction — `UNKNOWN` still means "the bundled file
  states none".
- **Packaging:** `hands-up.md` and `workshop.md` are now `export-ignore` next
  to `/CAIRN.md` and are named in `Tools/verify_release.sh`'s exclusion list.
  New `TacoTip_Extras/.gitattributes` and new `Tools/verify_release_extras.sh`
  give the Extras package its own rules and its own check.
- **Notices:** `TacoTip_Extras/THIRD_PARTY_NOTICES.md` rewritten against
  current facts (product "TacoTip Extras" 1.2.3, enforced minimum TacoTip
  0.8.0 from `TacoTipAdapter.lua:44`, the `tacotip-gearscore` URL, the
  GearScoreTBCClassic attribution aligned with the main notices, full MIT text
  kept). The main `THIRD_PARTY_NOTICES.md` now carries that attribution and
  the MIT notice **inline** — the main add-on ships `gearscore.lua`, so the
  notice cannot live in a file the package does not contain — and the dangling
  `bench/OPEN-ITEMS.md` pointer is gone.
- **Current state:** `Tools/verify_release.sh` → PASS, 27 files.
  `Tools/verify_release_extras.sh` → PASS, 29 files. Main harness → 70/70.
  Extras harness → 42/42 **on the first run of this session**; it then went
  red mid-session (3 invocations, then 5, 2 checks each: "level-70 policy …
  renders a NUMERIC Potential GS / Delta") because the **other lane was
  editing `TacoTip_Extras/Tests/harness/load_test.lua`, `Scoring.lua` and
  `Scanner.lua` in parallel** — the file mtimes and the changing failure set
  both proved it, and the suite went back to **42/42** once their edits
  settled. Not ours to fix, and we did not touch Extras code.
- **`TacoTip_Extras/CHANGELOG.md` also carries a short "Release packaging and
  licence notes" subsection** in its `[1.2.3]` section, recording the notices
  rewrite and the new packaging rules — the notices file ships inside the
  Extras package, so the change is user-visible there.
- **Dead end worth recording:** git's `export-ignore` is **not** scoped per
  archive. A nested `.gitattributes` that re-opens (`!export-ignore`) a path
  overrides the parent for that path **in every archive**, so a nested
  "re-open" leaks the Extras files into the TacoTip package. What does work is
  reading the two rule sets in **different scopes**: the TacoTip archive is
  built from the repository root (paths repo-relative), the Extras archive from
  the subtree (`git archive HEAD:TacoTip_Extras`, paths subtree-relative), and
  the root rule — which names the `TacoTip_Extras/` prefix — does not match
  there. In the subtree scope, `--worktree-attributes` reads the **root**
  file, not the nested one; without the flag git reads the **committed**
  nested file. The verifier therefore prefers the committed tree and falls
  back to the working tree before the file is committed, and it also asserts
  the nested file still declares every rule.
- **Next step:** the owning lane must change `TacoTip_Extras/README.md`
  (exact text below). Then commit, and re-run the Extras harness once the
  other lane's edits settle.

### Final verification (all green, run after the other lane's edits settled)
- `bash Tools/verify_release.sh` → **PASS**, 27 files, exit 0.
- `bash Tools/verify_release_extras.sh` → **PASS**, 29 files, exit 0.
- `bash Tests/harness/run_all.sh` → **70 invocations: 70 passed, 0 failed**.
- `bash TacoTip_Extras/Tests/harness/run_all.sh` → **42 invocations: 42 passed,
  0 failed**.

### For the lane that owns `TacoTip_Extras/README.md`
Two claims in that file are false as of 2026-10-19 and were **not** edited
here (not my file):

1. `TacoTip_Extras/README.md:25` — `status: unreleased`. The CurseForge
   listing **exists**: `https://www.curseforge.com/wow/addons/tacotip-extras`
   answers **HTTP 200** (title "TacoTip Extras"). Its file list shows
   **v1.2.2** (108 downloads), **v1.2.1** (29) and **v1.2.0** (11) published;
   **v1.2.3 is not uploaded yet**. Suggested: `status: released` if 1.2.3
   ships with 0.8.4, otherwise keep `unreleased` but say *what* is unreleased.
2. `TacoTip_Extras/README.md:175` — "**Not yet released.** The add-on is
   unreleased under its current packaging; the CurseForge listing does not
   exist yet." The second clause is **false** — the listing exists and has
   three published versions. Suggested replacement:
   "**Not yet released at 1.2.3.** The CurseForge listing exists and serves
   1.2.2; 1.2.3 ships with TacoTip 0.8.4."
3. Also stale in that file (found, not mine): `project_url:` and the body link
   at `:33` use `…/tacotip-extras/preview`, the pre-publication form. The
   verified live URL is `…/tacotip-extras`; the main README now uses that.
   And `:35` still says the add-on is "not maintained by the TacoTip author"
   — authorship was unified on AcidBomb in 1.2.0 (`TacoTip_Extras/CHANGELOG.md`,
   1.2.0 row).

**How the listing was verified:** `curl` gets **HTTP 403** from
`www.curseforge.com` (both slugs) and the legacy v2 API host does not
connect. `webfetch` returns **200** for `…/tacotip-extras/preview` (307 →
`…/tacotip-extras`) and for `…/tacotip-extras/files/all`, and
`media.forgecdn.net/attachments/2065/485/2-png.png` (the banner the main
README embeds) is **200 image/png, 39130 bytes**.
