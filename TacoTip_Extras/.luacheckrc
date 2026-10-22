-- luacheck config for TacoTip_Extras.
--
-- SELF-CONTAINED ON PURPOSE. luacheck loads ONE config per checked file (the
-- nearest .luacheckrc, or exactly what --config names). The repository-root
-- .luacheckrc describes TacoTip's WoW surface and is not loaded when this
-- directory is checked on its own -- so this file carries the add-on's own.
-- Run it as:
--
--   cd TacoTip_Extras && luacheck .
--
-- and from the repository root as:
--
--   luacheck TacoTip_Extras
--
-- Both are meaningful; the second uses the root config, so a few names here
-- are deliberately re-declared even though the root also knows them.

std = "lua51"

max_line_length = 500

-- Blizzard API this add-on reads. Every entry here is a real WoW global: they
-- were read out of the add-on's own source, not out of a "whatever luacheck
-- complained about" list, so a typo still fails the check.
read_globals = {
    "C_Item",
    "CreateFrame",
    "DEFAULT_CHAT_FRAME",
    "GetInventoryItemID",
    "GetInventoryItemLink",
    "GetItemStats",
    "GetTime",
    "GetWeaponEnchantInfo",
    "GUIDIsPlayer",
    -- The engine's taint-containment global, present on every supported
    -- client (Blizzard captures it as a local the same way it captures
    -- `forceinsecure`: Blizzard_FrameXML/SharedPetBattleTemplates.lua:5
    -- `local securecall = securecall;`). Read, never written.
    "securecall",
    -- WoW's server wall clock (epoch seconds). RankDB stamps and validates
    -- records with it, RankBrowser renders relative times from it, and Scanner
    -- stamps inspection records with it. It is a Blizzard global, not a
    -- missing local, and every call site guards it.
    "GetServerTime",
    "UIDropDownMenu_AddButton",
    "UIDropDownMenu_CreateInfo",
    "UIDropDownMenu_Initialize",
    "UIDropDownMenu_SetSelectedValue",
    "UIDropDownMenu_SetText",
    "UIDropDownMenu_SetWidth",
    "UnitClass",
    "UnitExists",
    "UnitGUID",
    "UnitIsPlayer",
    "UnitLevel",
}

globals = {
    -- Core.lua registers /ttgsdebug and Options.lua registers /ttgs. Both
    -- write through _G today (an earlier revision wrote one of them as a BARE
    -- global while the other used _G, so the same slash-command pair was
    -- declared two different ways). The live names are declared here so a
    -- revert to the bare form fails the check instead of shipping.
    "SLASH_TTEXTRASDEBUG1",
    "SLASH_TTEXTRAS1",
    -- SlashCmdList must be WRITABLE, not merely readable: both files assign
    -- fields on it at initialize time.
    "SlashCmdList",
    -- TacoTip's globals, read only through _G by the adapter.
    "TACOTIP_LOCALE",
    "TacoTip",
    "TacoTipConfig",
    "TacoTip_GSCallback",
    "TT_GS",
    "TT_PAWN",
}

-- Offline harness. It loads the real add-on against a mocked client, so it
-- legitimately installs globals on _G that the add-on never does. Keyed both
-- ways so the entry applies from the repository root and from inside the
-- add-on.
local harness = {
    read_globals = {
        -- `table.unpack` is permitted HERE ONLY. It does not exist in the Lua
        -- 5.1 WoW ships, so the shipped add-on must never use it -- the harness
        -- may, because it resolves `local unpack = unpack or table.unpack` to
        -- run the same suite under lua5.4 as well. Leaving the field off the
        -- top-level `table` entry keeps 5.4-only API out of the runtime.
        table = { fields = { "unpack" } },
        "arg",
    },
    globals = {
        "_G",
        "SlashCmdList",
        "TacoTip",
        "TacoTipConfig",
        "TacoTipExtrasDB",
        "TacoTip_GSCallback",
        "TT",
        "TT_GS",
        "TT_PAWN",
    },
}

files["Tests/harness/*.lua"] = harness
files["TacoTip_Extras/Tests/harness/*.lua"] = harness

-- Locale files are DATA, not code. A translated help paragraph is one long
-- string by design: splitting it to satisfy a 500-column limit would put line
-- breaks inside a sentence that is rendered as one line in game. The measured
-- effect is that the same paragraph is 1000+ columns in Russian.
files["Locale/*.lua"] = {
    max_line_length = false,
}