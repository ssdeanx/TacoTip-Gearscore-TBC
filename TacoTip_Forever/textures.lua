local addOnName = ...
local TT = _G[addOnName]
if (not TT) then
    TT = {}
    rawset(_G, addOnName, TT)
end

-- ============================================================================
-- FONTS
-- ============================================================================
TT.builtinTooltipFonts = {
    { value = "Fonts\\2002.TTF",                text = "Blizzard - 2002" },
    { value = "Fonts\\2002B.TTF",               text = "Blizzard - 2002 Bold" },
    { value = "Fonts\\ARIALN.TTF",              text = "Blizzard - Arial Narrow" },
    { value = "Fonts\\BLEI00D.TTF",             text = "Blizzard - Blei 00D" },
    { value = "Fonts\\FRIZQT__.TTF",            text = "Blizzard - Friz Quadrata TT" },
    { value = "Fonts\\FRIZQT_.TTF",             text = "Blizzard - Friz Quadrata" },
    { value = "Fonts\\K_Damage.TTF",            text = "Blizzard - Damage" },
    { value = "Fonts\\K_Pagetext.TTF",          text = "Blizzard - Page Text" },
    { value = "Fonts\\MORPHEUS.TTF",            text = "Blizzard - Morpheus" },
    { value = "Fonts\\SKURRI.TTF",              text = "Blizzard - Skurri" },
    { value = "Fonts\\FNT_Details_Combat.TTF",  text = "Blizzard - Details Combat" },
    { value = "Fonts\\FNT_Details_Bold.TTF",    text = "Blizzard - Details Bold" },
    { value = "Fonts\\FNT_Details_Hitech.TTF",  text = "Blizzard - Details Hitech" },
    { value = "Fonts\\FNT_Details_Heavy.TTF",   text = "Blizzard - Details Heavy" },
    { value = "Fonts\\FNT_Details_Outline.TTF", text = "Blizzard - Details Outline" },
    { value = "Fonts\\FNT_Details_Brush.TTF",   text = "Blizzard - Details Brush" },
    { value = "Fonts\\FNT_Details_Brush2.TTF",  text = "Blizzard - Details Brush 2" },
    -- CJK fonts (available when client locale matches)
    { value = "Fonts\\ZYHei.TTF",               text = "Blizzard - ZY Hei" },
    { value = "Fonts\\ZYKai_Casual.TTF",        text = "Blizzard - ZY Kai Casual" },
    { value = "Fonts\\ZYKai_T.TTF",             text = "Blizzard - ZY Kai T" },
    { value = "Fonts\\ZYMing.TTF",              text = "Blizzard - ZY Ming" },
    { value = "Fonts\\ZYMing_Casual.TTF",       text = "Blizzard - ZY Ming Casual" },
    { value = "Fonts\\ZYKow_Casual.TTF",        text = "Blizzard - ZY Kow Casual" },
}

-- ============================================================================
-- STATUSBAR TEXTURES (bar fills)
-- ============================================================================
-- Audited 0.7.9 against the Gethe/wow-ui-textures mirror. Of the 59 entries
-- this list held: 7 confirmed present, 29 refuted and removed, 23 unverified and
-- kept. The refuted run was mostly "<Frame>-BarFill" invented per panel -- the
-- raid bars are the clearest case, where only Raid-Bar-Hp-Fill and
-- Raid-Bar-Resource-Fill exist and the other five power names did not; Blizzard
-- ships one resource bar, not one per class resource.
TT.builtinStatusBarTextures = {

    -- TargetingFrame
    { value = "Interface\\TargetingFrame\\UI-StatusBar",                text = "Blizzard - Status Bar" },
    { value = "Interface\\TargetingFrame\\UI-TargetingFrame-BarFill",   text = "Blizzard - Targeting Bar Fill" },

    -- PaperDollInfoFrame
    { value = "Interface\\PaperDollInfoFrame\\UI-Character-Skills-Bar", text = "Blizzard - Character Skills Bar" },

    -- RaidFrame
    { value = "Interface\\RaidFrame\\Raid-Bar-Hp-Fill",                 text = "Blizzard - Raid Bar HP" },

    -- CastingBar
    { value = "Interface\\CastingBar\\UI-CastingBar-Border",            text = "Blizzard - Casting Bar" },
    { value = "Interface\\CastingBar\\UI-CastingBar-Spark",             text = "Blizzard - Casting Bar Spark" },

    -- TrainerFrame
    { value = "Interface\\TrainerFrame\\Trainer-BarFill",               text = "Blizzard - Trainer Bar" },

    -- ReputationFrame
    { value = "Interface\\ReputationFrame\\Reputation-BarFill",         text = "Blizzard - Reputation Bar" },
    { value = "Interface\\ReputationFrame\\Reputation-BarFill2",        text = "Blizzard - Reputation Bar 2" },

    -- HonorFrame / PvPFrame
    { value = "Interface\\HonorFrame\\Honor-BarFill",                   text = "Blizzard - Honor Bar" },

    -- CaptureBar
    { value = "Interface\\CaptureBar\\CaptureBar-BarFill",              text = "Blizzard - Capture Bar" },

    -- WorldState (Capture the flag, etc)
    { value = "Interface\\WorldState\\WorldState-BarFill",              text = "Blizzard - World State Bar" },

    -- Scenario
    { value = "Interface\\Scenario\\Scenario-BarFill",                  text = "Blizzard - Scenario Bar" },

    -- ChallengeMode
    { value = "Interface\\ChallengeMode\\ChallengeMode-BarFill",        text = "Blizzard - Challenge Mode Bar" },

    -- DungeonFind
    { value = "Interface\\DungeonFind\\DungeonFind-BarFill",            text = "Blizzard - Dungeon Finder Bar" },

    -- ObjectiveTracker
    { value = "Interface\\ObjectiveTracker\\Objective-BarFill",         text = "Blizzard - Objective Tracker Bar" },

    -- Artifact
    { value = "Interface\\Artifact\\Artifact-BarFill",                  text = "Blizzard - Artifact Bar" },

    -- Covenant
    { value = "Interface\\Covenant\\Covenant-BarFill",                  text = "Blizzard - Covenant Bar" },

    -- OrderHall
    { value = "Interface\\OrderHall\\OrderHall-BarFill",                text = "Blizzard - Order Hall Bar" },

    -- BattlePet
    { value = "Interface\\BattlePet\\BattlePet-BarFill",                text = "Blizzard - Battle Pet Bar" },

    -- Mounts
    { value = "Interface\\Mounts\\Mounts-BarFill",                      text = "Blizzard - Mount Bar" },

    -- Archaeology
    { value = "Interface\\Archaeology\\Archaeology-BarFill",            text = "Blizzard - Archaeology Bar" },

    -- GlyphFrame
    { value = "Interface\\GlyphFrame\\Glyph-BarFill",                   text = "Blizzard - Glyph Bar" },

    -- Stable
    { value = "Interface\\Stable\\Stable-BarFill",                      text = "Blizzard - Stable Bar" },

    -- Vehicle
    { value = "Interface\\Vehicle\\Vehicle-BarFill",                    text = "Blizzard - Vehicle Bar" },

    -- LossOfControl
    { value = "Interface\\LossOfControl\\LOC-BarFill",                  text = "Blizzard - Loss of Control Bar" },

    -- Platform / Minigame
    { value = "Interface\\Platform\\Platform-BarFill",                  text = "Blizzard - Platform Bar" },

    -- PetBattle
    { value = "Interface\\PetBattle\\PetBattle-XP-Bar",                 text = "Blizzard - Pet Battle XP" },

    -- LFGuild
    { value = "Interface\\LFGuild\\LFGuild-BarFill",                    text = "Blizzard - LF Guild Bar" },

    -- Buttons
    { value = "Interface\\Buttons\\WHITE8X8",                           text = "Blizzard - Solid" },
}

-- Per-client default border texture.
--
-- Verified: the Classic family reaches its NineSlice through
-- TooltipBackdropTemplate, while Retail and WoW Forever reach theirs through
-- SharedTooltipArtTemplate, so the two pairs really do build tooltips
-- differently. A single hardcoded default cannot serve both.
--
-- Verified 0.7.9: Interface\Tooltips\UI-Tooltip-Border exists on BOTH branches
-- of the Gethe/wow-ui-textures art mirror, byte-identical at 128x16, so it
-- serves all five clients from one path. This replaces an earlier guess at
-- UI-Backdrop-Edge, which the same mirror showed to be absent. The
-- "which art path either pair ships" question that used to be open here is
-- now closed; what remains per-client is the edge SIZE, which is 16 because
-- 14 is not a multiple of 8.
--
-- This is the FALLBACK, not a stored preference. A player who has picked a
-- border keeps it on every client. It applies when nothing is configured, or
-- when the configured value matches no entry in the list -- which is the case for
-- the historical default "Tooltip enlarged", a label that was never an entry and
-- so always resolved here.
--
-- Resolved lazily and defensively: it must never raise on the way, and the
-- library may not be present yet.
function TT:GetDefaultTooltipBorder()
    return "Interface\\Tooltips\\UI-Tooltip-Border"
end

-- Per-client default background, for the same reason. Only consumed on the legacy
-- full-backdrop path, which no current client takes, but kept in step with the
-- border so the two defaults cannot drift apart.
function TT:GetDefaultTooltipBackground()
    return "Interface\\Tooltips\\UI-Tooltip-Background"
end

-- ============================================================================
-- BACKGROUND TEXTURES (bgFile)
-- ============================================================================
-- Audited 0.7.9 against the Gethe/wow-ui-textures mirror. Of the 77 entries
-- this list held: 15 confirmed present, 39 refuted and removed, 23 unverified
-- and kept. The refuted run was almost entirely the invented
-- "<Frame>-Background" pattern: LootFrame, MailFrame, OptionsFrame, Spellbook,
-- PvPFrame, Garrison and the rest do not carry a file by that name, even
-- though their directories are in the mirror. Several have real art under a
-- different name (MailFrame ships UI-MailFrameBG and MailItemBorder;
-- Garrison ships GarrisonUIBackground) -- which is the point. A path that does
-- not resolve renders as a missing-texture placeholder, never an error.
TT.builtinTooltipBackgrounds = {

    -- DialogFrame
    { value = "Interface\\DialogFrame\\UI-DialogBox-Background",                       text = "Blizzard - Dialog Background" },
    { value = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",                  text = "Blizzard - Dialog Background Dark" },
    { value = "Interface\\DialogFrame\\UI-DialogBox-Gold-Background",                  text = "Blizzard - Dialog Background Gold" },
    { value = "Interface\\DialogFrame\\UI-DialogBox-Header",                           text = "Blizzard - Dialog Header" },

    -- FullScreenTextures
    { value = "Interface\\FullScreenTextures\\LowHealth",                              text = "Blizzard - Low Health" },
    { value = "Interface\\FullScreenTextures\\OutOfControl",                           text = "Blizzard - Out of Control" },

    -- FrameGeneral
    { value = "Interface\\FrameGeneral\\UI-Background-Marble",                         text = "Blizzard - Marble" },
    { value = "Interface\\FrameGeneral\\UI-Background-Rock",                           text = "Blizzard - Rock" },

    -- AchievementFrame
    { value = "Interface\\AchievementFrame\\UI-Achievement-Parchment-Horizontal",      text = "Blizzard - Parchment" },
    { value = "Interface\\AchievementFrame\\UI-GuildAchievement-Parchment-Horizontal", text = "Blizzard - Parchment 2" },

    -- TabardFrame
    { value = "Interface\\TabardFrame\\TabardFrameBackground",                         text = "Blizzard - Tabard Background" },

    -- Tooltips
    { value = "Interface\\Tooltips\\UI-Tooltip-Background",                            text = "Blizzard - Tooltip Background" },

    -- ItemText
    { value = "Interface\\ItemText\\ItemText-Background",                              text = "Blizzard - Item Page" },

    -- GameTimeFrame
    { value = "Interface\\GameTimeFrame\\GameTimeFrameBackground",                     text = "Blizzard - Game Time" },

    -- Minimap
    { value = "Interface\\Minimap\\UI-Minimap-Background",                             text = "Blizzard - Minimap" },

    -- TutorialFrame
    { value = "Interface\\TutorialFrame\\TutorialFrameBackground",                     text = "Blizzard - Tutorial" },

    -- OrderHall
    { value = "Interface\\OrderHall\\OrderHall-Background",                            text = "Blizzard - Order Hall BG" },

    -- Covenant
    { value = "Interface\\Covenant\\Covenant-Background",                              text = "Blizzard - Covenant BG" },

    -- Artifact
    { value = "Interface\\Artifact\\Artifact-Background",                              text = "Blizzard - Artifact BG" },

    -- Scenario
    { value = "Interface\\Scenario\\Scenario-Background",                              text = "Blizzard - Scenario BG" },

    -- Bank
    { value = "Interface\\Bank\\Bank-Background",                                      text = "Blizzard - Bank BG" },

    -- GuildBank
    { value = "Interface\\GuildBank\\GuildBank-Background",                            text = "Blizzard - Guild Bank BG" },

    -- PartyFrame
    { value = "Interface\\PartyFrame\\PartyFrame-Background",                          text = "Blizzard - Party Frame BG" },

    -- Stable
    { value = "Interface\\Stable\\Stable-Background",                                  text = "Blizzard - Stable BG" },

    -- Trainer
    { value = "Interface\\Trainer\\Trainer-Background",                                text = "Blizzard - Trainer BG" },

    -- SocialHub
    { value = "Interface\\SocialHub\\SocialHub-Background",                            text = "Blizzard - Social Hub BG" },

    -- DungeonFind
    { value = "Interface\\DungeonFind\\DungeonFind-Background",                        text = "Blizzard - Dungeon Find BG" },

    -- BattlePet
    { value = "Interface\\BattlePet\\BattlePet-Background",                            text = "Blizzard - Battle Pet BG" },

    -- PetJournal
    { value = "Interface\\PetJournal\\PetJournal-Background",                          text = "Blizzard - Pet Journal BG" },

    -- Mounts
    { value = "Interface\\Mounts\\Mounts-Background",                                  text = "Blizzard - Mounts BG" },

    -- Archaeology
    { value = "Interface\\Archaeology\\Archaeology-Background",                        text = "Blizzard - Archaeology BG" },

    -- NOTE: an Interface\BackdropTextures\ block (Textured / Dark / Solid, plus
    -- their nine colour variants) used to sit here. It was removed on 0.7.9:
    -- there is no BackdropTextures directory on Retail at all. Verified against
    -- Gethe/wow-ui-textures -- the art mirror that sits beside wow-ui-source --
    -- where the path returns 404 on live. Those 19 entries were a fabrication, and
    -- a wrong texture path renders a missing-texture placeholder without raising
    -- anything, so they would have looked broken rather than failed loudly.
    -- Ornament
    { value = "Interface\\Ornament\\Ornament-Background",                              text = "Blizzard - Ornament" },

    -- UIWidgets
    { value = "Interface\\UIWidgets\\UIWidget-Background",                             text = "Blizzard - UI Widget BG" },

    -- Aidan (Art)
    { value = "Interface\\Aidan\\Aidan-Background",                                    text = "Blizzard - Aidan BG" },

    -- TalkingHead
    { value = "Interface\\TalkingHead\\TalkingHead-Background",                        text = "Blizzard - Talking Head BG" },

    -- LossOfControl
    { value = "Interface\\LossOfControl\\LOC-Background",                              text = "Blizzard - Loss of Control BG" },

    -- Warboard
    { value = "Interface\\Warboard\\Warboard-Background",                              text = "Blizzard - Warboard BG" },

    -- Buttons
    { value = "Interface\\Buttons\\WHITE8X8",                                          text = "Blizzard - Solid" },
}

-- ============================================================================
-- BORDER TEXTURES (edgeFile)
-- ============================================================================
-- Audited 0.7.9 against the Gethe/wow-ui-textures mirror. Of the 55 entries
-- this list held: 9 confirmed present, 24 refuted and removed, 22 unverified and
-- kept. Three more went on policy rather than on art evidence: the
-- Interface\AddOns\Details\images\border_1..3 entries are third-party Details
-- media sitting in a Blizzard art list, which is the same contradiction the
-- font filter acts on. SharedMedia already covers Details, and the filter below
-- drops the Details fonts for exactly that reason.
TT.builtinTooltipBorders = {

    -- AchievementFrame
    { value = "Interface\\AchievementFrame\\UI-Achievement-WoodBorder", text = "Blizzard - Achievement Wood" },

    -- ArenaEnemyFrame
    { value = "Interface\\ArenaEnemyFrame\\UI-Arena-Border",            text = "Blizzard - Arena Border",      edgeSize = 32 },

    -- Buttons
    { value = "Interface\\Buttons\\UI-SliderBar-Border",                text = "Blizzard - Slider Bar",       edgeSize = 8 },

    -- CharacterFrame
    { value = "Interface\\CHARACTERFRAME\\UI-Party-Border",             text = "Blizzard - Party Border" },

    -- DialogFrame
    { value = "Interface\\DialogFrame\\UI-DialogBox-Border",            text = "Blizzard - Dialog Border" },
    { value = "Interface\\DialogFrame\\UI-DialogBox-Gold-Border",       text = "Blizzard - Dialog Border Gold" },

    -- FriendsFrame
    { value = "Interface\\FriendsFrame\\UI-Toast-Border",               text = "Blizzard - Toast Border",      edgeSize = 12 },

    -- Glues / Common
    { value = "Interface\\Glues\\Common\\TextPanel-Border",             text = "Blizzard - Text Panel",       edgeSize = 16 },

    -- Tooltips
    { value = "Interface\\Tooltips\\ChatBubble-Backdrop",               text = "Blizzard - Chat Bubble" },
    { value = "Interface\\Tooltips\\UI-Tooltip-Border",                 text = "Blizzard - Tooltip Border" },

    -- Tooltips, themed. Present on Retail and WoW Forever, ABSENT from the
    -- Classic art mirror (verified against Gethe/wow-ui-textures: 35 files under
    -- Tooltips/ on live, 23 on classic, and the three themed borders appear only
    -- on live). They are the texture-path equivalents of Blizzard's own modern
    -- TooltipAzeriteLayout / TooltipCorruptedLayout / TooltipMawLayout NineSlice
    -- layouts, and all three are 256x32, so they slice at edgeSize 32 rather than
    -- the 16 the plain border uses. Listed unconditionally for simplicity; a
    -- Classic player who picks one gets a missing-texture placeholder, which is
    -- why each carries its own edgeSize below rather than sharing the global one.
    { value = "Interface\\Tooltips\\UI-Tooltip-Border-Azerite",   text = "Blizzard - Tooltip Azerite",   edgeSize = 32 },
    { value = "Interface\\Tooltips\\UI-Tooltip-Border-Corrupted", text = "Blizzard - Tooltip Corrupted", edgeSize = 32 },
    { value = "Interface\\Tooltips\\UI-Tooltip-Border-Maw",       text = "Blizzard - Tooltip Maw",       edgeSize = 32 },

    -- TutorialFrame
    { value = "Interface\\TutorialFrame\\UI-TutorialFrame-CalloutGlow", text = "Blizzard - Tutorial Glow",    edgeSize = 16 },

    -- TrainingFrame
    { value = "Interface\\TrainingFrame\\TrainingFrame-Border",         text = "Blizzard - Training Frame" },

    -- PetFrame
    { value = "Interface\\PetFrame\\PetFrame-Border",                   text = "Blizzard - Pet Frame" },

    -- StableFrame
    { value = "Interface\\StableFrame\\StableFrameBorder",              text = "Blizzard - Stable Frame" },

    -- OrderHall
    { value = "Interface\\OrderHall\\OrderHall-Border",                 text = "Blizzard - Order Hall Border" },

    -- Covenant
    { value = "Interface\\Covenant\\Covenant-Border",                   text = "Blizzard - Covenant Border" },

    -- Artifact
    { value = "Interface\\Artifact\\Artifact-Border",                   text = "Blizzard - Artifact Border" },

    -- Scenario
    { value = "Interface\\Scenario\\Scenario-Border",                   text = "Blizzard - Scenario Border" },

    -- Bank
    { value = "Interface\\Bank\\Bank-Border",                           text = "Blizzard - Bank Border" },

    -- PartyFrame
    { value = "Interface\\PartyFrame\\PartyFrame-Border",               text = "Blizzard - Party Frame Border" },

    -- Stable
    { value = "Interface\\Stable\\StableFrame-Border",                  text = "Blizzard - Stable Frame Border" },

    -- Trainer
    { value = "Interface\\Trainer\\TrainerFrame-Border",                text = "Blizzard - Trainer Frame Border" },

    -- DungeonFind
    { value = "Interface\\DungeonFind\\DungeonFind-Border",             text = "Blizzard - Dungeon Find Border" },

    -- BattlePet
    { value = "Interface\\BattlePet\\BattlePet-Border",                 text = "Blizzard - Battle Pet Border" },

    -- PetJournal
    { value = "Interface\\PetJournal\\PetJournal-Border",               text = "Blizzard - Pet Journal Border" },

    -- Mounts
    { value = "Interface\\Mounts\\Mounts-Border",                       text = "Blizzard - Mounts Border" },

    -- Archaeology
    { value = "Interface\\Archaeology\\Archaeology-Border",             text = "Blizzard - Archaeology Border" },

    -- TalkingHead
    { value = "Interface\\TalkingHead\\TalkingHead-Border",             text = "Blizzard - Talking Head Border" },

    -- Ornament
    { value = "Interface\\Ornament\\Ornament-Border",                   text = "Blizzard - Ornament Border" },

}

-- ============================================================================
-- PER-CLIENT FILTERING
-- ============================================================================
-- The tables above are candidate Blizzard asset paths. They were NOT harvested
-- from Retail's FrameXML -- that was the claim until 0.7.9 and it was false:
-- only 22 of the 191 entries then listed appear in origin/live FrameXML at all,
-- and the rest were invented in the shape Blizzard's naming convention would
-- suggest. See the audit note at the head of each list below.
--
-- Every path is now classified against Gethe/wow-ui-textures, the art mirror
-- that sits beside wow-ui-source, which carries the real client Interface tree
-- (repo root IS the Interface folder; there is no "Interface/" prefix). It is
-- calibrated: 96% of the non-addon paths origin/live FrameXML references resolve
-- in its live branch, 95% for classic_era against its classic branch. So
-- ABSENCE inside a directory that IS present is evidence, while absence of the
-- whole directory is not. A second check asks whether any wow-ui-source branch
-- mentions the name at all, so a renamed-but-real file is not pruned.
--
-- Offering a path that cannot resolve is worse than not offering it:
-- Texture:SetTexture silently no-ops on a missing file, so the user picks
-- "Chromie Time Border", the swatch renders blank, and the tooltip ends up with
-- an invisible or solid-white border with no indication of why. Nothing raises,
-- so the harness could never have caught this by running the code.
--
-- Tests/harness/textures.txt is the reviewed allow-list that keeps the lists
-- from drifting back, and textures_test.lua fails on any path absent from it.
--
-- Two filters are applied to the FONT list:
--
--   1. CJK fonts. Fonts\ZY*.TTF only ship on zhCN and zhTW clients. On any
--      other locale selecting one silently falls back to the default font.
--
--   2. Details fonts. FNT_Details_*.TTF belong to the third-party Details
--      addon, not Blizzard, and were mislabelled "Blizzard - Details ...".
--      Third-party media is LibSharedMedia's job -- it is an OptionalDependency
--      and options.lua already reads every media list through it -- so these
--      are dropped from the built-in list rather than mislabelled. The same
--      argument retired the three Interface\AddOns\Details\images\border_*
--      entries from the BORDER list on 0.7.9; shipping a Details border inside
--      the Blizzard art list contradicted the rule this comment states.
--
-- NOT filtered here: the Retail-only paths (Warboard*, Covenant*, Azerite*,
-- Artifact*, and so on). Removing them per client would mean either tagging
-- every entry individually or probing texture existence at runtime, and
-- neither is worth the regression risk in a correctness pass. They are left in
-- place; SharedMedia users get a correct list either way because LibSharedMedia
-- takes precedence when present.
local function ttFilterFontList(list)
    if (type(list) ~= "table") then return list end
    local locale = (type(GetLocale) == "function") and GetLocale() or "enUS"
    local isCJK = (locale == "zhCN" or locale == "zhTW")
    local out = {}
    for _, entry in ipairs(list) do
        local value = entry.value or ""
        local isCJKFont = (value:find("Fonts\\ZY", 1, true) ~= nil)
        local isDetailsFont = (value:find("FNT_Details_", 1, true) ~= nil)
        -- keep: everything that is not CJK-on-a-non-CJK-client, and not Details
        local keep = true
        if isCJKFont and not isCJK then
            keep = false
        elseif isDetailsFont then
            keep = false
        end
        if keep then
            out[#out + 1] = entry
        end
    end
    return out
end

TT.builtinTooltipFonts = ttFilterFontList(TT.builtinTooltipFonts)
