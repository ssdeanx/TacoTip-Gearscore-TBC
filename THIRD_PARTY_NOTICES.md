# Third-party notices — TacoTip

TacoTip is licensed under the **MIT License**; see [LICENSE](LICENSE).

The libraries bundled under `Libs/` are separate works and are **not** covered
by TacoTip's MIT terms. Each retains its own copyright, license terms and
warranty disclaimer, recorded below as stated by its own files — MIT permission
does not extend to them, and none of them may be relicensed under it.

Nothing here grants any right to the bundled libraries beyond what their own
terms allow. TacoTip bundles them unmodified.

License and author statements are taken **only** from each library's own bundled
files, with the source line quoted. Where a bundled file states no license, the
entry says `UNKNOWN` — nothing is asserted here from memory, from upstream
listings, or from convention.

## Libraries loaded by this addon

`TacoTip.toc` loads exactly these four libraries (lines 11–14); they are the
entire bundled-library surface of the addon:

| Library | License | Author / credits | Bundled header |
| :--- | :--- | :--- | :--- |
| `LibStub` | Public Domain | Kaelten, Cladhaire, ckknight, Mikk, Ammo, Nevcairiel, joshborke | `Libs/LibStub/LibStub.lua` |
| `CallbackHandler-1.0` | UNKNOWN | UNKNOWN | `Libs/CallbackHandler-1.0/CallbackHandler-1.0.lua` |
| `LibDetours-1.0` | UNKNOWN | kebabstorm | `Libs/LibDetours-1.0/LibDetours-1.0.lua` |
| `LibForeverInspector` | UNKNOWN | UNKNOWN | `Libs/LibForeverInspector/LibForeverInspector.lua` |

### LibStub

- **File:** `Libs/LibStub/LibStub.lua`
- **License:** Public Domain — stated in the file's own header (line 3).
- **Credits:** Kaelten, Cladhaire, ckknight, Mikk, Ammo, Nevcairiel, joshborke
  — stated in the file's own header (line 4).

The header states verbatim:

> LibStub is hereby placed in the Public Domain
>
> Credits: Kaelten, Cladhaire, ckknight, Mikk, Ammo, Nevcairiel, joshborke

Public Domain is a dedication with no conditions attached, so it imposes no
obligation on TacoTip or on anyone downstream. `Libs/LibStub/LibStub.toc`
repeats the statement (`## X-License: Public Domain`).

### CallbackHandler-1.0

- **File:** `Libs/CallbackHandler-1.0/CallbackHandler-1.0.lua`
- **License:** **UNKNOWN.** The file contains no license statement — nothing in
  it mentions a license, a copyright or a permission grant.
- **Author:** **UNKNOWN.** The file states no author or copyright. Its only
  identifying line is the header's SVN keyword line (line 1), quoted verbatim:

  > `--[[ $Id: CallbackHandler-1.0.lua 1186 2018-07-21 14:19:18Z nevcairiel $ ]]`

  That keyword line records the committer field of the revision, not an
  authorship or copyright statement.

An earlier revision of this file asserted an MIT license for CallbackHandler-1.0
attributed to Icedragon. That assertion was not reproducible from anything
bundled in this repository, so it is withdrawn here and replaced with UNKNOWN
pending verification.

### LibDetours-1.0

- **File:** `Libs/LibDetours-1.0/LibDetours-1.0.lua`
- **License:** **UNKNOWN.** The file contains no license statement.
- **Author:** kebabstorm — stated in the file's own header (line 3).

The header states verbatim:

> LibDetours-1.0 by kebabstorm

The separately bundled `Libs/LibDetours-1.0/LibDetours-1.0.toc` disagrees: it
carries `## Author: AcidBomb` (line 5). The two bundled files contradict each
other, so the author is recorded from the library's own Lua header and the
contradiction is left standing rather than resolved by assumption.

An earlier revision of this file asserted an MIT license for LibDetours-1.0.
That assertion was not reproducible from anything bundled in this repository, so
it is withdrawn here and replaced with UNKNOWN pending verification.

### LibForeverInspector

- **File:** `Libs/LibForeverInspector/LibForeverInspector.lua`
- **License:** **UNKNOWN.** The file contains no license statement. TacoTip's
  own [LICENSE](LICENSE) (MIT, Copyright (C) 2026 AcidBomb) states that bundled
  third-party libraries under `Libs/` are separately licensed and excludes them
  from its terms; no bundled file states whether this library counts as such,
  and no file states a license for it.
- **Author:** **UNKNOWN.** The file contains no author or copyright statement.

The header (lines 1–9) describes the library as a "Universal multi-engine
inspection & specialization library", lists the clients it supports and
declares its requirements (LibStub, CallbackHandler-1.0) — and nothing about
authorship or licensing.

An earlier revision of this file stated that the library is "part of the TacoTip
project" and covered by TacoTip's own LICENSE. Nothing bundled supports either
claim, so both are withdrawn here and replaced with UNKNOWN pending a written
decision.

## Vendored under `Libs/` but not loaded — not part of this release

Two further directories are vendored under `Libs/`:

- `Libs/LibDataBroker-1.1/` — a single file, `LibDataBroker-1.1.lua`
- `Libs/LibDBIcon-1.0/` — `LibDBIcon-1.0.lua` and `lib.xml`

**Neither is loaded by TacoTip.** `TacoTip.toc`'s only library loads are the
four listed above; no `.toc` file loads either directory, and no Lua or XML
file outside those two directories loads or calls into them. The only mention
of `LibDBIcon` outside its own directory is a comment in `main.lua` that cites
the file to record that it owns a separate tooltip frame — a citation, not a
load.

**Neither is part of a TacoTip release.** A release package is built by
`Tools/verify_release.sh`, which exports the repository's tracked files with
`git archive` — from HEAD by default, or from the current working tree with
`--worktree` — and lets the `export-ignore` rules in `.gitattributes` decide
what ends up in it. Two of those rules name the vendored directories
explicitly:

    /Libs/LibDataBroker-1.1/** export-ignore
    /Libs/LibDBIcon-1.0/** export-ignore

Those two rules are what govern the package: a package carries tracked files
only, and the rules filter both directories out of it — so neither appears in a
package, and neither can appear in one if the directories are ever added to
git.

Both are **pending license verification** and neither receives a license or
author statement here:

- `LibDataBroker-1.1.lua` has no header comment block at all — the file opens
  with its LibStub / CallbackHandler-1.0 asserts — and states no license.
- `LibDBIcon-1.0.lua`'s header identifies it only by name, a one-line
  description and the CurseForge slug comment
  `--@curseforge-project-slug: libdbicon-1-0@` (line 1), and states no license;
  `lib.xml` states none either.

Until that verification is complete, these two directories must not be added to
`TacoTip.toc` and must not be represented as licensed.

This is **OPEN**. Its closing conditions: upstream license, source, author and
version verified and this file updated from that evidence; an adoption decision
recorded; and a guarded load seam plus harness coverage before either library
ships.

(The workshop register that used to carry this row as "row 21",
`bench/OPEN-ITEMS.md`, has been removed from the repository. The open item and
its closing conditions are recorded here instead, so this file no longer
points at a document that does not exist.)

---

## Attribution outside this repository

### GearScore scoring

GearScore scoring behavior derives from **GearScoreTBCClassic** by yrodrigez,
using the authoritative CurseForge package labelled `v1.1.1-release`. This
package ships the derived scoring code (`gearscore.lua`), so the attribution
and the required license notice are reproduced **here, in full**, rather than
by reference to a document this package does not contain.

Original work © 2024 gk646
Fork maintenance and updates © 2026 Community contributors

The required GearScoreTBCClassic license notice follows in full:

> MIT License
>
> Copyright (c) 2024 gk646
>
> Permission is hereby granted, free of charge, to any person obtaining a copy
> of this software and associated documentation files (the "Software"), to deal
> in the Software without restriction, including without limitation the rights
> to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
> copies of the Software, and to permit persons to whom the Software is
> furnished to do so, subject to the following conditions:
>
> The above copyright notice and this permission notice shall be included in all
> copies or substantial portions of the Software.
>
> THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
> IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
> FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
> AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
> LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
> OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
> SOFTWARE.

The same attribution is carried by the companion add-on in
[TacoTip Extras' THIRD_PARTY_NOTICES.md](TacoTip_Extras/THIRD_PARTY_NOTICES.md).
That is a **repository path**: the TacoTip package ships this file and does not
ship that one, which is why the notice is reproduced above in full.

### Upstream TacoTip lineage

This project's ancestry includes an earlier TacoTip distribution credited to
`anzz1`. Where that lineage's own licensing is not recorded in this repository,
no additional rights or grants are asserted here beyond what this repository's
LICENSE covers for the current work.

---

## Accuracy note

Everything above is sourced to files in this repository, quoted with their file
paths and line numbers. Packaging rules are the exception: they are cited as
the rule itself, because a rule — not a line number — is what governs a
package, and `.gitattributes` does not ship, so a reader of the published
package cannot check a line number in it. Where a bundled file states no
license or author, the entry says `UNKNOWN` instead of repeating a claim from
outside the repository — three such claims (MIT for `CallbackHandler-1.0`,
MIT for `LibDetours-1.0`, and project coverage for `LibForeverInspector`) stood
in earlier revisions of this file and have been withdrawn because nothing
bundled here supports them.

If any attribution here is found to be inaccurate, please open an issue.