---
description: 11-Locale translation parity, format specifier safety, and fallback rules
globs: ["Locale/*.lua"]
---

# Rule 05: Localization Parity Standards

- **Source of Truth:** All new text keys must be added to `Locale/enUS.lua` first (239 base keys).
- **100% Key Coverage:** All 10 localized files (`deDE`, `esES`, `esMX`, `frFR`, `itIT`, `koKR`, `ptBR`, `ruRU`, `zhCN`, `zhTW`) must maintain 100% key parity with `enUS.lua`.
- **Format Specifier Safety:** Format tokens (`%s`, `%d`) in translated strings must strictly match the count, type, and order of the English source string.
- **Maintainer Credits:** `TEXT_HELP_WELCOME` must maintain the standard signature `AcidBomb (Pilsung)` across all locales.
