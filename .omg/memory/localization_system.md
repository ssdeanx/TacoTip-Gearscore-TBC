# Localization Engine & Internationalization

## 1. Source of Truth & Fallback Merge

- `Locale/enUS.lua` is the definitive source of truth containing exactly **263 base translation keys**.
- All localized tables (`deDE`, `esES`, `esMX`, `frFR`, `itIT`, `koKR`, `ptBR`, `ruRU`, `zhCN`, `zhTW`) inherit English values via the metatable fallback merge:

  ```lua
  setmetatable(L, { __index = function(_, k) return TACOTIP_LOCALE_enUS and TACOTIP_LOCALE_enUS[k] or k end })
  ```

---

## 2. Parity & Safety Invariants

- **100% Key Parity:** Every locale file must define all 263 keys with no missing entries.
- **Format Specifier Safety:** If an English string contains `%s` or `%d`, all translated versions must contain the exact same count and types of format tokens.
- **Maintainer Integrity:** Maintainer credit strings (`TEXT_HELP_WELCOME`) preserve the standard author signature `AcidBomb (Pilsung)`.

---

## 3. Dynamic Language Switching

- Config key: `TacoTipConfig.locale_override` (e.g. `"zhCN"`, `"enUS"`, `"deDE"`).
- Default: `nil` (matches client locale `GetLocale()`).
- Changing the language selector in the Root options page updates `locale_override` and prompts for UI reload.
