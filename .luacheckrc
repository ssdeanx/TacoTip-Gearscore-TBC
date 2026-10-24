std = "lua51"

max_line_length = 500
unused_args = false

read_globals = {
    -- WoW extends the standard `table` library with wipe(); it is a real global
    -- field on every supported client (28-37 Blizzard call sites per branch).
    -- Preferred over the bare `wipe` global, which is protected on 10.0+.
    table = { fields = { "wipe" } },
    "BackdropTemplateMixin",
    "C_AddOns",
    "C_Item",
    "C_Map",
    "C_NamePlate",
    "C_PaperDollInfo",
    "C_PlayerInfo",
    "C_SpecializationInfo",
    "C_Timer",
    "Enum",
    "TooltipDataProcessor",
    "TooltipUtil",
    "UnitTokenFromGUID",
    "GetAverageItemLevel",
    "GetSpecialization",
    "GetSpecializationInfo",
    "GetSpecializationInfoByID",
    -- WoW's server wall clock (epoch seconds). Read by TacoTip Extras'
    -- RankDB/RankBrowser/Scanner; the addon's own .luacheckrc already declares
    -- it, but this root config also governs `luacheck TacoTip_Extras` from the
    -- repository root, so it must know the name too.
    "GetServerTime",
    "CANCEL",
    "CanInspect",
    "CastingBarMixin",
    "CharacterModelFrame",
    "CheckInteractDistance",
    "Clamp",
    "ClearAchievementComparisonUnit",
    "CONTAINER_OFFSET_X",
    "CONTAINER_OFFSET_Y",
    "CreateFrame",
    "GetNumTalentGroups",
    "CUSTOM_CLASS_COLORS",
    "DetachTooltip",
    "ERR_INVALID_INSPECT_TARGET",
    "ERR_OUT_OF_RANGE",
    "ERR_UNIT_NOT_FOUND",
    "EventRegistry",
    "GameTooltip",
    "GameTooltipStatusBar",
    "GetAchievementComparisonInfo",
    "GetAchievementInfo",
    "GetActiveTalentGroup",
    "GetAddOnMetadata",
    "GetBestMapForUnit",
    "GetBuildInfo",
    "GetClassAtlas",
    "GetComparisonAchievementPoints",
    "GetComparisonStatistic",
    "GetCursorPosition",
    "GetCVar",
    "GetCVarBool",
    "GetGlyphSocketInfo",
    "GetGuildInfo",
    "GetGuildRosterInfo",
    "GetInventoryItemID",
    "GetInventoryItemLink",
    "GetInventoryItemMixin",
    "GetItemInfo",
    "GetItemInfoInstant",
    "GetLastCacheTime",
    "GetLocale",
    "GetMouseFoci",
    "GetMouseFocus",
    "GetNumGuildMembers",
    "GetNumTalentGroups",
    "GetNumTalents",
    "GetNumTalentsByClass",
    "GetPlayerInfoByGUID",
    "GetQuestDifficultyColor",
    "GetRealmName",
    "GetSpecialization",
    "GetSpecializationName",
    "GetStatistic",
    "GetTalentInfo",
    "GetTalentInfoByClass",
    "GetTalentPoints",
    "GetTime",
    "GetTotalAchievementPoints",
    "GRAY_FONT_COLOR",
    "HIGHLIGHT_FONT_COLOR",
    "hooksecurefunc",
    -- The engine's taint-containment global. Blizzard captures it as a local
    -- the same way it captures `forceinsecure`
    -- (Blizzard_FrameXML/SharedPetBattleTemplates.lua:5
    -- `local securecall = securecall;`), and it is present on every supported
    -- client. Read, never written.
    "securecall",
    "InCombatLockdown",
    "InspectFrame",
    "InspectModelFrame",
    "InspectPaperDollFrame",
    "InterfaceOptions_AddCategory",
    "InterfaceOptionsFrame_OpenToCategory",
    "IsEquippableItem",
    "IsGUIDInGroup",
    "IsInGroup",
    "IsInGuild",
    "IsInRaid",
    "IsModifierKeyDown",
    "IsShiftKeyDown",
    "ItemRefTooltip",
    "LE_PARTY_CATEGORY_HOME",
    "LE_PARTY_CATEGORY_INSTANCE",
    "LibSharedMedia",
    "LibStub",
    "LOCALIZED_CLASS_NAMES_MALE",
    "Mixin",
    "MultiBarBottomRight",
    "MultiBarLeft",
    "MultiBarRight",
    "NORMAL_FONT_COLOR",
    "NotifyInspect",
    "PaperDollFrame",
    "PawnClassicLastUpdatedVersion",
    -- Pawn's own registries. PawnCommon.Scales is the exact table Pawn looks a
    -- scale name up in, and PawnScaleProviders holds the registered provider
    -- names; pawn.lua reads both to resolve the library prefix per client without
    -- calling an API that reports an unknown name by printing to chat.
    "PawnCommon",
    "PawnScaleProviders",
    "PawnGetItemData",
    "PawnGetScaleColor",
    "PawnGetSingleValueFromItem",
    "PlayerCastingBarFrame",
    "PowerBarColor",
    "print",
    "RAID_CLASS_COLORS",
    "RequestLoadItemDataByID",
    "RESET",
    "SAVE",
    "select",
    "SetAchievementComparisonUnit",
    "SetCVar",
    "SetPortraitTexture",
    "SetPortraitZoom",
    "Settings",
    "ShoppingTooltip1",
    "ShoppingTooltip2",
    "SlashCmdList",
    "StaticPopupDialogs",
    "StaticPopup_Show",
    "strfind",
    "strlen",
    "strlower",
    "strrep",
    "strreplace",
    "strsub",
    "time",
    "tinsert",
    "tremove",
    "UIDropDownMenu",
    "UIDropDownMenu_AddButton",
    "UIDropDownMenu_CreateInfo",
    "UIDropDownMenu_Initialize",
    "UIDropDownMenu_SetSelectedValue",
    "UIDropDownMenu_SetText",
    "UIParent",
    "UIParentManagedFrameMixin",
    "UIErrorsFrame",
    "UnitCanAttack",
    "UnitClass",
    "UnitClassification",
    "UnitExists",
    "UnitFactionGroup",
    "UnitFrameTarget",
    "UnitGUID",
    "UnitGroupRolesAssigned",
    "UnitInParty",
    "UnitInRaid",
    "UnitIsConnected",
    "UnitIsDeadOrGhost",
    "UnitIsOtherPlayersPet",
    "UnitIsPlayer",
    "UnitIsPVP",
    "UnitIsSameServer",
    "UnitIsUnit",
    "UnitLevel",
    "UnitName",
    "UnitOnTaxi",
    "UnitPower",
    "UnitPowerMax",
    "UnitPowerType",
    "UnitPVPName",
    "UnitRace",
    "unpack",
    "wipe",
    "WorldFrame",
    "AchievementFrame",
    "AchievementFrameComparison",
    "AchievementFrameComparison_OnEvent",
    "APIDocumentation",
    "geterrorhandler",
}

globals = {
    "InspectAvgItemLvl",
    "InspectAvgItemLvlText",
    "InspectGearScore",
    "InspectGearScoreText",
    "PersonalAvgItemLvl",
    "PersonalAvgItemLvlText",
    "PersonalGearScore",
    "PersonalGearScoreText",
    "SLASH_TACOTIP1",
    "SLASH_TACOTIP2",
    "SLASH_TACOTIP3",
    "SLASH_TACOTIP4",
    "SLASH_TACOTIP5",
    "SLASH_TACOTIP6",
    "SLASH_TACOTIP7",
    "TacoTipConfig",
    "TacoTipDragButton",
    "TacoTipMouseAnchor",
    "TacoTipPowerBar",
    "TacoTip_CustomPosEnable",
    "TacoTip_GSCallback",
    "TACOTIP_LOCALE",
    "TACOTIP_LOCALES",
    "TT_GS",
    "TT_PAWN",
}

-- The stale in-repo copy of the add-on (never packaged: export-ignored, never
-- loaded). It still carries the one legacy global the current tree dropped, so
-- the name is declared HERE, scoped to that copy, rather than in the global
-- list where it would claim the live tree depends on it.
files["OLD/*.lua"] = {
    globals = {
        "_TacoTipPawnReady",
    },
}

files["Locale/*.lua"] = {
    -- Locale files are DATA, not code: a translated help paragraph is one long
    -- string by design (the same paragraph is 1000+ columns in Russian), so the
    -- column limit is waived for them. Same waiver the add-on's own config
    -- applies to TacoTip_Extras/Locale/*.lua.
    max_line_length = false,
    read_globals = {
        "GetLocale",
    },
    globals = {
        "TACOTIP_LOCALE",
        "TACOTIP_LOCALES",
    },
}

files["Libs/LibClassicInspector/LibClassicInspector.lua"] = {
    read_globals = {
        "C_SpecializationInfo",
        "GetActiveTalentGroup",
        "GetNumTalentGroups",
    },
    globals = {},
}

-- Offline verification harnesses. These load the real addon against a mocked
-- WoW environment, so they legitimately touch globals the addon never does.
files["Tests/harness/*.lua"] = {
    read_globals = {
        -- The mocked client's error-message API. The harness reproduces the
        -- client's own path (UIErrorsFrame.lua:140-149): the message is added
        -- first and the sound is played second, from the same function, with
        -- the sound kit id read from GetGameMessageInfo.
        "GetGameMessageInfo",
        "C_Sound",
        "PlaySound",
        -- `table.unpack` is permitted HERE ONLY. It does not exist in the Lua
        -- 5.1 WoW ships, so the shipped addon must never use it -- the harnesses
        -- may, because they resolve `local unpack = unpack or table.unpack` to run
        -- the same suite under lua5.4 as well. Leaving the field off the
        -- top-level `table` entry is deliberate: it keeps 5.4-only API out of
        -- the runtime.
        table = { fields = { "unpack" } },
    },
    globals = {
        "ERRORS",
        "COLOR_APPLIED",
        "DROPDOWN_SETS",
        "LEGACY_LOG",
        "PICKER_COLOR",
        "PICKER_INFO",
        "SETTINGS_LOG",
        "POSTCALLS",
        "ADDLINE_CALLS",
        "TACO_TIP_DEBUG",
        "TALENTS",
        "TALENT_QUERIES",
        "TALENT_GROUP_POINTS",
        "TALENT_ACTIVE_GROUP",
        "TIMERS",
    },
    -- A harness routinely shadows a mocked global (TT, TT_GS) with a local
    -- stand-in; that shadowing is the test's mechanism, not a defect.
    shadowing = false,
    unused = false,
}

-- TacoTip Extras is a SEPARATE add-on with its own .luacheckrc. That config is
-- self-contained and is what `cd TacoTip_Extras && luacheck .` uses. These
-- blocks mirror it so the whole repository can also be linted in one command
-- from the root (`luacheck .`) without false positives.
files["TacoTip_Extras/*.lua"] = {
    read_globals = {
        "DEFAULT_CHAT_FRAME",
        "GetItemStats",
        "GetWeaponEnchantInfo",
        "GUIDIsPlayer",
        "UIDropDownMenu_SetWidth",
    },
}

-- Locale files are DATA, not code: a translated help paragraph is one long
-- string by design, so the column limit is waived for them (same waiver the
-- add-on's own config applies).
files["TacoTip_Extras/Locale/*.lua"] = {
    max_line_length = false,
}

files["TacoTip_Extras/Tests/harness/*.lua"] = {
    read_globals = {
        table = { fields = { "unpack" } },
        "arg",
    },
    shadowing = false,
}

-- Vendored third-party library. It keeps upstream's own terms and style, so
-- it is linted for undefined names only -- never for unused locals.
files["Libs/LibDBIcon-1.0/*.lua"] = {
    read_globals = {
        "GetMinimapShape",
        "Minimap",
        "WOW_PROJECT_ID",
        "WOW_PROJECT_MAINLINE",
    },
    -- The library registers its icon on the compartment frame, so that global
    -- is written to, not only read.
    globals = {
        "AddonCompartmentFrame",
    },
    unused = false,
}
