# Localization Engine & Internationalization

## 1. Source of Truth & Fallback Merge

- `Locale/enUS.lua` is the definitive source of truth containing **239 base translation keys**.
- No locale file writes `_G.TACOTIP_LOCALE` directly; each registers its table into `_G.TACOTIP_LOCALES[<code>]`. `_G.TacoTipApplyLocale()` (in `Locale/enUS.lua`, loaded **last**) resolves `TacoTipConfig.locale_override` / `GetLocale()` and fills `_G.TACOTIP_LOCALE` in place by copy-merge rather than a metatable:
  - File-scope `local L = _G.TACOTIP_LOCALE` references remain valid across overrides.
  - Missing keys fall back to `enUS` at load time and stay fixed until reload.

---

## 2. Parity & Safety Invariants

- **100% Key Parity:** All 11 locale files (`enUS`, `deDE`, `esES`, `esMX`, `frFR`, `itIT`, `koKR`, `ptBR`, `ruRU`, `zhCN`, `zhTW`) must match all 239 keys (`Tests/harness/locale_test.lua`).
- **Lookup Resolution:** `load_test.lua` scans addon sources for `L["Key"]` lookups (handling escaped `\n` keys and legitimate numeric config constants like offsets/font sizes) and fails on any `nil` lookup.
- **Format Specifier Safety:** Translated strings must preserve identical `%s`/`%d` count and types against `enUS`.
- **No Invented Translations:** Never invent missing Blizzard class/spec strings; verify client strings via FrameXML / `wago.tools`.
- **Attribution Integrity:** Keep author/credit strings (`TEXT_HELP_WELCOME`, headers, `THIRD_PARTY_NOTICES.md`) intact (`AcidBomb (Pilsung)` & original TacoTip `kebabstorm`).
