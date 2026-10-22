# verify-ru-spec-names — Journal

## 2026-10-20 — Desk opened
- **Purpose:** verify every Russian specialization name in `LibForeverInspector`'s `spec_table_localized` against citable Russian sources, with no invented Russian, and record the confirmation status in the tree.
- **Scope:** the ruRU Monk / Demon Hunter / Evoker entries (`Libs/LibForeverInspector/LibForeverInspector.lua:360-393`) and the pin that asserts them (`Tests/harness/specname_test.lua`). Names only — no locale restructure, no other locale touched.
- **Next step:** fetch the cited sources, cross-check every name against a second one, apply only what is verified, and report what could not be confirmed.

## 2026-10-20 — Every name verified; no name changed
- **Worked on:** fetched Blizzard's own Russian class pages (monk, demon-hunter, evoker) and then cross-checked each name against a SECOND Russian source. All eight names in the tree are confirmed: Monk **Хмелевар / Ткач туманов / Танцующий с ветром**, Demon Hunter **Истребление / Месть**, Evoker **Опустошитель / Хранитель / Насыщатель**. Index alignment against `lib.spec_table` confirmed for every pair.
- **Changed in the tree:** COMMENTS ONLY, no value touched. (1) the library's ruRU comment now records the verification date, the second source per class, the index-alignment contract, and why the Demon Hunter's third spec is absent; (2) `specname_test.lua`'s header records the same cross-check and the "Пожиратель" note. No pin assertion changed.
- **Current state:** green — `bash Tests/harness/run_all.sh` → 71/71, `luacheck .` → 0 warnings / 0 errors in 88 files, `Tests/harness/specname_test.lua` → ALL PASS (15 checks).
- **Why nothing was applied:** no name needed changing. The values already in the tree are Blizzard's own Russian client strings, so there is nothing to apply and — per the operator's rule — **no changelog entry for names that were not applied**.
- **Also learned (a trap worth keeping):** Blizzard's Russian Demon Hunter page lists a THIRD spec, **"Пожиратель"** (Devourer), added in Midnight (retail 11.2). It is NOT in the table on purpose: the classic clients this library serves do not have it, and `lib.spec_table` has no third entry to align it with. A maintainer who verifies against that page and "fixes" the list alone would push "Месть" out of index with "Vengeance" and print the wrong spec for every Demon Hunter. Both comment blocks now say so.
- **Could not reproduce (reported, not rewritten):** the 0.8.4 changelog bullet says the names were "cross-checked against the Russian WoW Wiki and the Russian WoW database". The Russian WoW Wiki leg could NOT be reproduced — every `warcraft.wiki.gg/ru/...` path redirects to the English main page, raw or percent-encoded title alike — so the wiki's Russian pages are not reachable with a plain fetch. The wowhead.ru leg IS visible in the indexed snippet (its live pages are JS-rendered). That clause belongs to another desk's entry and its names are correct, so it was left alone rather than rewritten from another desk's claim.
- **Next step:** none for the names. If the operator wants the changelog's cross-check clause restated in terms that a reader can reproduce, that is a one-clause edit in the 0.8.4 section — say so and it is done.

## 2026-10-20 — Second pass on the operator's source root (Wowhead ru) + wago.tools DB
- **Worked on:** the operator supplied `https://www.wowhead.com/ru/` as the source root. The class-guide paths under it do not exist in the Russian locale (`/ru/guide/classes/monk` → "Страница не найдена"), but the per-spec **talent-calculator** pages do, and each carries the client's own class+spec name in its heading — all eight names read directly off Wowhead's Russian locale, one page per spec, with the exact URLs quoted in the library comment and in the pin header.
- **Cross-check the operator asked for:** warcraft.wiki.gg's `/ru/` pages are unreachable (every path lands on the English main page — confirmed with a JS-rendering scraper as well as a plain fetch), so the operator's alternative was used: **wago.tools' DB2**. The client's own strings live in table **`ChrSpecialization`** (`Name_lang`), retail build **12.1.7.70424**, locale **ruRU** — `wago.tools/db2/ChrSpecialization/csv?build=12.1.7.70424&locale=ruRU`. It gives the names WITH their `OrderIndex`, and `ChrClasses` gives the class names.
- **A correction to my own earlier claim:** I had written that adding "Пожиратель" to the Russian list "would push 'Месть' out of index alignment with 'Vengeance'". That was WRONG — appending an index-2 entry does not shift indexes 0 and 1, and the DB proves the client's own OrderIndex for the Demon Hunter is 0=Истребление, 1=Месть, 2=Пожиратель. Both comment blocks were rewritten to the accurate reason: the two tables are kept the same shape because `lib.spec_table` has no third ENGLISH entry, and a Russian row with no English counterpart would name a spec the rest of the table cannot name. A wrong claim in a comment is worse than no comment.
- **Also confirmed from the DB:** the ruRU MAGE row that has been in the tree all along (Тайная магия / Огонь / Лед) matches the client's own `ChrSpecialization` rows for ClassID 8 exactly — the whole ruRU table, not just the three changed classes.
- **Current state:** green — 71/71 harness, luacheck 0/0 in 88 files, verify_release PASS, `specname_test.lua` ALL PASS.
- **Next step:** none. No name was changed, so no changelog entry was added for names.

## 2026-10-20 — [signal:done] second pass: Wowhead ru primary + wago.tools DB cross-check
- All eight names read directly off `www.wowhead.com/ru/talent-calc/<class>/<spec>` (exact URLs and quoted headings in the library comment and the pin header).
- Cross-checked in the client's own DB2 strings (`ChrSpecialization.Name_lang`, retail 12.1.7.70424, ruRU) with `OrderIndex`, plus `ChrClasses` for the class names; warcraft.wiki.gg's `/ru/` pages are unreachable and are reported as such.
- My own earlier comment claim about index shifting was wrong and was corrected in place.
- No value changed; no changelog entry added.
- Signal: `desks/verify-ru-spec-names/.signals/2026-10-20T16-58-00Z.json`.

## 2026-10-20 — [signal:done] all eight Russian spec names verified, none changed
- Sources: Blizzard's three Russian class pages + a second Russian source per class (wow.gg/ru guides; murloville.ru).
- Tree change: comments only — provenance and the Пожиратель note, in the library and in the pin's header. No value, no assertion, no changelog entry.
- Verified: 71/71 harness, luacheck 0/0 in 88 files, `specname_test.lua` ALL PASS.
- Signal: `desks/verify-ru-spec-names/.signals/2026-10-20T16-35-00Z.json`.
