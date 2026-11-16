# Third-party notices — TacoTip Extras

TacoTip Extras is distributed under the MIT License; see [LICENSE](LICENSE). The
following notices cover upstream reference work and external dependencies.

Nothing here grants any right to the works named below beyond what their own
terms allow.

License and author statements are taken from the sources named against each
entry. Where the source states no license, the entry says `UNKNOWN` — nothing
is asserted here from memory, from an upstream listing, or from convention.

## TacoTip GearScore Enhancer (Reference & Upstream Base)

Multiple components of TacoTip Extras are derived from or inspired by
**[TacoTip GearScore Enhancer](https://www.curseforge.com/wow/addons/tacotip-gearscore-enhancer)**
by **NS**, distributed under the MIT License:

> MIT License
>
> Copyright (c) 2026 NS
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

- **Parts derived from TacoTip GearScore Enhancer (`Copyright (c) 2026 NS`):**
  the companion add-on structure (`TacoTipAdapter` / tooltip & frame takeover),
  enhancement metric model (Current GS, Potential GS, Delta, Completion,
  Average iLvl, Unenhanced GS, enchant/gem bonus rules, slot policies, and the
  level-70 potential/completion display rule in `Scoring.lua`), session LRU
  cache concept (`Cache.lua`), gear-slot scanning & item-load retry model
  (`Scanner.lua`), player tooltip display modes (`Disabled`/`Minimal`/`Compact`/`Detailed`
  in `Tooltips.lua`), Character/Inspect summary frames and unlock handles
  (`Frames.lua`), Options foundation (`Options.lua`), and minimap toggle concept
  (`Minimap.lua`).
- **Parts changed or added in TacoTip Extras (`Copyright (c) 2026 AcidBomb`):**
  renamed add-on and separated SavedVariables (`TacoTipExtrasDB` instead of
  `TacoTipGearScoreEnhancerDB`), removed duplicated GearScore formulas so base
  GearScore always delegates to TacoTip's `TT_GS`, replaced hardcoded version
  checks with `>= 0.8.0` capability probing against `LibForeverInspector`,
  built the Server-Wide Leaderboard & P2P Sync Engine (`RankDB.lua`,
  `RankSync.lua`, `RankBrowser.lua`, tooltip `GS Rank:` lines, and `/tt`
  dashboard integration), switched slash commands to `/ex` / `/extras` / `/tte`,
  added full five-client support (Classic Era, TBC Anniversary, Titanforge, WoW
  Forever/Camelot, Retail) with Mainline `TooltipDataProcessor` polling,
  `securecall` taint containment, `issecretvalue`/`canaccessvalue` guards,
  11-locale translations (`Locale/*.lua`), 128-entry caching, async
  cross-reload/city seeding & WoW Forever async capture slices, and automated
  multi-interpreter test harnesses.

## GearScoreTBCClassic

GearScore calculation behavior is derived from **GearScoreTBCClassic** by
yrodrigez, using the authoritative CurseForge package labelled
`v1.1.1-release`. The independently implemented compatibility rules retain
attribution to the original work and to the maintained fork:

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

GearScoreTBCClassic source and assets are not bundled with TacoTip Extras.

## TacoTip

[TacoTip](https://www.curseforge.com/wow/addons/tacotip-gearscore) is a
required external dependency. `TacoTip_Extras.toc` declares
`## Dependencies: TacoTip`, so TacoTip loads first and nothing in TacoTip
Extras works without it.

**Version.** TacoTip Extras **1.3.1** enforces a **minimum TacoTip version of
0.8.0** — the constant `MINIMUM_TACOTIP_VERSION = { 0, 8, 0 }` at
`TacoTip_Extras/TacoTipAdapter.lua:44` — and then probes the capabilities it
actually calls. It deliberately does **not** compare the inspector's version:
`LibForeverInspector` registers the `LibClassicInspector` alias at minor 2 and
defines no `Version()` method at all, so an equality check against a published
version could never pass. A minimum version is still enforced, so a genuinely
older TacoTip is still refused.

**License.** TacoTip is distributed under the MIT License — MIT,
Copyright (C) 2026 AcidBomb — as stated in the `LICENSE` file that ships with
the TacoTip add-on. TacoTip Extras neither restates nor extends those terms.

TacoTip is not bundled, modified, redistributed or forked by TacoTip Extras.
No TacoTip source, libraries, localizations, artwork or other assets are
included in the TacoTip Extras package; TacoTip and its components remain
governed by their own terms.

TacoTip and TacoTip Extras are separate CurseForge projects with separate
listings, written and maintained by the same author. TacoTip Extras is not a
fork of TacoTip and implies no endorsement by TacoTip or by anyone else.

## Libraries reached through TacoTip

TacoTip Extras calls `LibForeverInspector` — the multi-engine inspection
library TacoTip loads from its own `Libs/` directory. **TacoTip Extras does
not bundle it**; it reaches the library through TacoTip.

- **License:** **UNKNOWN.** The bundled file states no license.
- **Author:** **UNKNOWN.** The bundled file states no author.

Those two answers are TacoTip's, recorded with the file and line each was read
from in [TacoTip's THIRD_PARTY_NOTICES.md](../THIRD_PARTY_NOTICES.md) — a
**repository path**, since the TacoTip Extras package ships
`TacoTip_Extras/` on its own and does not ship that file. They are reproduced
here unchanged rather than resolved by assumption. A license claim for this
library is **not** made by this document.

## Accuracy note

Everything above is sourced to the file or the listing named against it. Where
a source states no license or author, the entry says `UNKNOWN` instead of
repeating a claim from outside this repository.

If any attribution here is found to be inaccurate, please open an issue.
