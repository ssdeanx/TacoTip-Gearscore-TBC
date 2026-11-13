# Third-party notices — TacoTip

TacoTip is licensed under the **MIT License**; see [LICENSE](LICENSE).

The libraries bundled under `Libs/` carry their **own** licenses and are **not**
covered by TacoTip's MIT terms. Each retains its original copyright, license,
and warranty disclaimer — MIT permission does not extend to them, and none of
them may be relicensed under it.

Nothing here grants any right to the bundled libraries beyond what their own
terms allow. TacoTip bundles them unmodified.

| Library | License | Author |
| :--- | :--- | :--- |
| `LibStub` | Public Domain | Kaelten, Cladhaire, ckknight, Mikk, Ammo, Nevcairiel, joshborke |
| `CallbackHandler-1.0` | MIT | Icedragon and contributors |
| `LibDetours-1.0` | MIT | kebabstorm |
| `LibDataBroker-1.1` | Public Domain | Tekkub and contributors |
| `LibDBIcon-1.0` | Public Domain (CurseForge `libdbicon-1-0`) | Rabbit, funkehdude and contributors |
| `LibForeverInspector` | MIT | AcidBomb (part of this project) |

The three fonts under `Media/Fonts/` are third-party too, each under its own
license, shipped unmodified beside its own license file so a package carries
both:

| Font | File | License | Copyright |
| :--- | :--- | :--- | :--- |
| Noto Sans Regular | `Media/Fonts/NotoSans-Regular.ttf` | SIL OFL 1.1 (`OFL-NotoSans.txt`) | The Noto Project Authors |
| NanumGothic Regular | `Media/Fonts/NanumGothic-Regular.ttf` | SIL OFL 1.1 (`OFL-NanumGothic.txt`) | NHN Corporation / Naver |
| WenQuanYi Micro Hei | `Media/Fonts/WenQuanYiMicroHei.ttf` | Apache 2.0 (`LICENSE-WenQuanYiMicroHei.txt`) | WenQuanYi Project contributors |

They are used only to draw a player name or a guild name whose script the
client's own face cannot draw (a Russian or Chinese guild name on an English
client). The WenQuanYi file is face 0 of the upstream `.ttc`, extracted with
fontTools without touching a glyph; the other two are the upstream TTFs as
published.

---

## LibStub

- **File:** `Libs/LibStub/LibStub.lua`
- **License:** Public Domain
- **Copyright / credits:** Kaelten, Cladhaire, ckknight, Mikk, Ammo, Nevcairiel,
  joshborke

The library's own header states verbatim:

> LibStub is hereby placed in the Public Domain

Public Domain is a dedication with no conditions attached, so it imposes no
obligation on TacoTip or on anyone downstream.

## CallbackHandler-1.0

- **File:** `Libs/CallbackHandler-1.0/CallbackHandler-1.0.lua`
- **License:** MIT
- **Copyright:** Icedragon (and contributors)

The full MIT permission notice and warranty disclaimer apply to it as published
upstream. The upstream distribution remains the authoritative copy of that text,
as it is not bundled in this repository.

## LibDetours-1.0

- **File:** `Libs/LibDetours-1.0/LibDetours-1.0.lua`
- **License:** MIT
- **Copyright:** kebabstorm

Declared in the library header as *LibDetours-1.0 by kebabstorm*. The full MIT
permission notice and warranty disclaimer apply as published upstream; the text
is not bundled in this repository.

## LibDataBroker-1.1

- **File:** `Libs/LibDataBroker-1.1/LibDataBroker-1.1.lua`
- **License:** Public Domain
- **Authors:** Tekkub and contributors

Public Domain dedication; bundled unmodified for `LibDBIcon-1.0` minimap
launcher registration.

## LibDBIcon-1.0

- **File:** `Libs/LibDBIcon-1.0/LibDBIcon-1.0.lua`
- **License:** Public Domain (CurseForge `libdbicon-1-0`, r167)
- **Authors:** Rabbit, funkehdude and contributors

Bundled unmodified single-file library (`LibDBIcon-1.0.lua`).

## LibForeverInspector

- **File:** `Libs/LibForeverInspector/LibForeverInspector.lua`
- **License:** MIT
- **Copyright:** AcidBomb

This library is part of the TacoTip project rather than a separate upstream
dependency, and is covered by TacoTip's own [LICENSE](LICENSE).

---

## Attribution outside this repository

### GearScore scoring

GearScore scoring behavior derives from **GearScoreTBCClassic** by yrodrigez,
using the authoritative CurseForge package labelled `v1.1.1-release`. The
required license notice for that work, and its attribution to the original
author and maintainers, are reproduced in full in
[TacoTip Extras' THIRD_PARTY_NOTICES.md](../TacoTip_Extras/THIRD_PARTY_NOTICES.md).

### Upstream TacoTip lineage

This project's ancestry includes an earlier TacoTip distribution credited to
`anzz1`. Where that lineage's own licensing is not recorded in this repository,
no additional rights or grants are asserted here beyond what this repository's
LICENSE covers for the current work.

---

## Accuracy note

License statements above were taken from each library's own source headers as
bundled in this repository. Where a library's complete license text is not
bundled alongside it, the upstream distribution is authoritative:

- LibStub — <http://www.wowace.com/addons/libstub/>
- CallbackHandler-1.0 — authored for the Wowpedia / WoWInterface library set
- LibDetours-1.0 — authored by kebabstorm

If any attribution here is found to be inaccurate, please open an issue.