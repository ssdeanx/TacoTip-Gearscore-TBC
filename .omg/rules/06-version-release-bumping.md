---
description: Synchronous version bumping protocol and dual attribution integrity across manifests and test pins
globs: ["TacoTip.toc", "main.lua", "options.lua", "README.md", "CHANGELOG.md", "LICENSE", "THIRD_PARTY_NOTICES.md", "Tests/harness/load_test.lua"]
---

# Rule 06: Version Release Bumping & Attribution Protocol

When bumping core **TacoTip**'s version, update every pinned location together and verify with `bash Tools/verify_release.sh --worktree`:
1. `TacoTip.toc`: `## Version: X.Y.Z`
2. `main.lua`: `addOnVersion` fallback string (`"X.Y.Z"`)
3. `options.lua`: `addOnVersion` fallback string (`"X.Y.Z"`)
4. `Tests/harness/load_test.lua`: version assertions pinned against TOC/addon fallback
5. `README.md`: badge/version notes and `What's New` section
6. `CHANGELOG.md`: version summary and `## [X.Y.Z]` release notes

Preserve dual copyright and upstream attribution (`AcidBomb` + original TacoTip author `kebabstorm`, `https://www.curseforge.com/wow/addons/tacotip-gearscore-talents`) across `LICENSE`, `THIRD_PARTY_NOTICES.md`, `TacoTip.toc`, `README.md`, and core module headers. Never modify `TacoTip_Extras/` during core TacoTip bumps.
