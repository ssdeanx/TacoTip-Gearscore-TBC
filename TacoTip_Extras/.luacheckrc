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
    -- Core.lua registers /ttgsdebug. NOTE THE ASYMMETRY: Core.lua assigns
    -- SLASH_TTGSEDEBUG1 as a BARE global while its own guard reads
    -- `SlashCmdList.TTGSEDEBUG ~= nil`, and Options.lua assigns
    -- _G.SLASH_TTGSE1 for /ttgs. Blizzard pairs a `SLASH_NAME1` global with
    -- `SlashCmdList.NAME`; the two files spell that pairing differently.
    -- Reported, NOT fixed -- it is runtime behaviour and phase 2 owns it.
    "SLASH_TTGSEDEBUG1",
    "SLASH_TTGSE1",
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