# Localization Engine & Internationalization

## 1. Source of Truth & Fallback Merge

- `Locale/enUS.lua` is the definitive source of truth containing exactly **239 base translation keys**.
- No locale file writes `_G.TACOTIP_LOCALE` directly; each only registers its own table into `_G.TACOTIP_LOCALES[<code>]`. `_G.TacoTipApplyLocale()` (in `Locale/enUS.lua`, loaded **last** so the merge has a base) then resolves the selection and fills `_G.TACOTIP_LOCALE` by **copy-merge**, not a metatable:

  ```lua
  for key in pairs(target) do target[key] = nil end
  for key, value in pairs(base) do target[key] = value end
  for key, value in pairs(defaults) do
    if (target[key] == nil) then target[key] = value end
  end
  ```

  Two consequences worth keeping: (a) because the target table is *filled in place* and never replaced, `main.lua`'s file-scope `local L = _G.TACOTIP_LOCALE` stays valid across a locale switch; (b) because it is a copy rather than a metatable, an untranslated key resolves to its **English** value at switch time and is then frozen into the table — adding a key to a locale file afterwards will not retroactively update a table that has already been merged.

---

## 2. Parity & Safety Invariants

- **100% Key Parity:** Every locale file must define all 239 keys with no missing entries.
- **Every lookup must resolve.** `load_test` scans the addon sources for literal `L["Key"]` lookups and asserts none resolve to `nil` in `_G.TACOTIP_LOCALE`. This replaced a `nlocale >= 251` magic threshold, which was only a proxy for the same idea: it went red when 24 genuinely unreferenced keys were pruned (nothing broken) while staying green if a *referenced* key was deleted. Two traps that assertion has to handle: keys containing `\n` are a two-character escape in source but a real newline once loaded (scan must unescape before comparing), and several keys are legitimately **numeric** (e.g. `["CHARACTER_FRAME_GS_TITLE_FONT_SIZE"] = 10`, the `*_XPOS`/`*_YPOS` frame offsets), so the check must test for `nil`, not for `type(...) ~= "string"`.
- **Format Specifier Safety:** If an English string contains `%s` or `%d`, all translated versions must contain the exact same count and types of format tokens.
- **Maintainer Integrity:** Maintainer credit strings (`TEXT_HELP_WELCOME`) preserve the standard author signature `AcidBomb (Pilsung)`.

---

## 3. Dynamic Language Switching

- Config key: `TacoTipConfig.locale_override` (e.g. `"zhCN"`, `"enUS"`, `"deDE"`).
- Default: `nil` (matches client locale `GetLocale()`).
- Changing the language selector in the Root options page updates `locale_override` and prompts for UI reload.
