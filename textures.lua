
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
    { value = "Fonts\\2002.TTF", text = "Blizzard - 2002" },
    { value = "Fonts\\2002B.TTF", text = "Blizzard - 2002 Bold" },
    { value = "Fonts\\ARIALN.TTF", text = "Blizzard - Arial Narrow" },
    { value = "Fonts\\BLEI00D.TTF", text = "Blizzard - Blei 00D" },
    { value = "Fonts\\FRIZQT__.TTF", text = "Blizzard - Friz Quadrata TT" },
    { value = "Fonts\\FRIZQT_.TTF", text = "Blizzard - Friz Quadrata" },
    { value = "Fonts\\K_Damage.TTF", text = "Blizzard - Damage" },
    { value = "Fonts\\K_Pagetext.TTF", text = "Blizzard - Page Text" },
    { value = "Fonts\\MORPHEUS.TTF", text = "Blizzard - Morpheus" },
    { value = "Fonts\\SKURRI.TTF", text = "Blizzard - Skurri" },
    { value = "Fonts\\FNT_Details_Combat.TTF", text = "Blizzard - Details Combat" },
    { value = "Fonts\\FNT_Details_Bold.TTF", text = "Blizzard - Details Bold" },
    { value = "Fonts\\FNT_Details_Hitech.TTF", text = "Blizzard - Details Hitech" },
    { value = "Fonts\\FNT_Details_Heavy.TTF", text = "Blizzard - Details Heavy" },
    { value = "Fonts\\FNT_Details_Outline.TTF", text = "Blizzard - Details Outline" },
    { value = "Fonts\\FNT_Details_Brush.TTF", text = "Blizzard - Details Brush" },
    { value = "Fonts\\FNT_Details_Brush2.TTF", text = "Blizzard - Details Brush 2" },
    -- CJK fonts (available when client locale matches)
    { value = "Fonts\\ZYHei.TTF", text = "Blizzard - ZY Hei" },
    { value = "Fonts\\ZYKai_Casual.TTF", text = "Blizzard - ZY Kai Casual" },
    { value = "Fonts\\ZYKai_T.TTF", text = "Blizzard - ZY Kai T" },
    { value = "Fonts\\ZYMing.TTF", text = "Blizzard - ZY Ming" },
    { value = "Fonts\\ZYMing_Casual.TTF", text = "Blizzard - ZY Ming Casual" },
    { value = "Fonts\\ZYKow_Casual.TTF", text = "Blizzard - ZY Kow Casual" },
}

-- ============================================================================
-- STATUSBAR TEXTURES (bar fills)
-- ============================================================================
TT.builtinStatusBarTextures = {

    -- TargetingFrame
    { value = "Interface\\TargetingFrame\\UI-StatusBar", text = "Blizzard - Status Bar" },
    { value = "Interface\\TargetingFrame\\UI-TargetingFrame-BarFill", text = "Blizzard - Targeting Bar Fill" },

    -- PaperDollInfoFrame
    { value = "Interface\\PaperDollInfoFrame\\UI-Character-Skills-Bar", text = "Blizzard - Character Skills Bar" },

    -- RaidFrame
    { value = "Interface\\RaidFrame\\Raid-Bar-Hp-Fill", text = "Blizzard - Raid Bar HP" },
    { value = "Interface\\RaidFrame\\Raid-Bar-Mana-Fill", text = "Blizzard - Raid Bar Mana" },
    { value = "Interface\\RaidFrame\\Raid-Bar-Energy-Fill", text = "Blizzard - Raid Bar Energy" },
    { value = "Interface\\RaidFrame\\Raid-Bar-Rage-Fill", text = "Blizzard - Raid Bar Rage" },
    { value = "Interface\\RaidFrame\\Raid-Bar-Focus-Fill", text = "Blizzard - Raid Bar Focus" },
    { value = "Interface\\RaidFrame\\Raid-Bar-RunicPower-Fill", text = "Blizzard - Raid Bar Runic" },

    -- CastingBar
    { value = "Interface\\CastingBar\\UI-CastingBar-Border", text = "Blizzard - Casting Bar" },
    { value = "Interface\\CastingBar\\UI-CastingBar-Spark", text = "Blizzard - Casting Bar Spark" },

    -- FriendsFrame
    { value = "Interface\\FriendsFrame\\FriendsFrame-StatusBar", text = "Blizzard - Friends XP Bar" },

    -- OptionsFrame
    { value = "Interface\\OptionsFrame\\UI-OptionsBar", text = "Blizzard - Options Bar" },

    -- TalentFrame
    { value = "Interface\\TalentFrame\\TalentFrame-ListItemFill", text = "Blizzard - Talent Fill" },

    -- Spellbook
    { value = "Interface\\Spellbook\\Spellbook-SkillRank", text = "Blizzard - Skill Rank" },

    -- CharacterFrame
    { value = "Interface\\CharacterFrame\\Character-Frame-Bar", text = "Blizzard - Character Bar" },

    -- ContainerFrame
    { value = "Interface\\ContainerFrame\\Container-Bar", text = "Blizzard - Container Bar" },

    -- GuildBankFrame
    { value = "Interface\\GuildBankFrame\\GuildBank-EmbossedFill", text = "Blizzard - Guild Bank Embossed" },

    -- TrainerFrame
    { value = "Interface\\TrainerFrame\\Trainer-BarFill", text = "Blizzard - Trainer Bar" },

    -- QuestFrame
    { value = "Interface\\QuestFrame\\QuestProgressBar", text = "Blizzard - Quest Progress" },

    -- TradeSkillFrame
    { value = "Interface\\TradeSkillFrame\\TradeSkill-BarFill", text = "Blizzard - Trade Skill Bar" },

    -- ReputationFrame
    { value = "Interface\\ReputationFrame\\Reputation-BarFill", text = "Blizzard - Reputation Bar" },
    { value = "Interface\\ReputationFrame\\Reputation-BarFill2", text = "Blizzard - Reputation Bar 2" },

    -- HonorFrame / PvPFrame
    { value = "Interface\\HonorFrame\\Honor-BarFill", text = "Blizzard - Honor Bar" },
    { value = "Interface\\PvPFrame\\PvP-BarFill", text = "Blizzard - PvP Bar" },

    -- LootFrame
    { value = "Interface\\LootFrame\\LootProgressBar", text = "Blizzard - Loot Progress" },

    -- BattlefieldFrame
    { value = "Interface\\BattlefieldFrame\\Battlefield-BarFill", text = "Blizzard - Battlefield Bar" },

    -- AuctionFrame
    { value = "Interface\\AuctionFrame\\AuctionFrame-BarFill", text = "Blizzard - Auction Bar" },

    -- CaptureBar
    { value = "Interface\\CaptureBar\\CaptureBar-BarFill", text = "Blizzard - Capture Bar" },

    -- WorldState (Capture the flag, etc)
    { value = "Interface\\WorldState\\WorldState-BarFill", text = "Blizzard - World State Bar" },

    -- EncounterJournal
    { value = "Interface\\EncounterJournal\\EncounterJournal-BarFill", text = "Blizzard - Encounter Journal Bar" },

    -- Scenario
    { value = "Interface\\Scenario\\Scenario-BarFill", text = "Blizzard - Scenario Bar" },

    -- ChallengeMode
    { value = "Interface\\ChallengeMode\\ChallengeMode-BarFill", text = "Blizzard - Challenge Mode Bar" },

    -- DungeonFind
    { value = "Interface\\DungeonFind\\DungeonFind-BarFill", text = "Blizzard - Dungeon Finder Bar" },

    -- ObjectiveTracker
    { value = "Interface\\ObjectiveTracker\\Objective-BarFill", text = "Blizzard - Objective Tracker Bar" },

    -- Artifact
    { value = "Interface\\Artifact\\Artifact-BarFill", text = "Blizzard - Artifact Bar" },

    -- Azerite
    { value = "Interface\\Azerite\\Azerite-BarFill", text = "Blizzard - Azerite Bar" },

    -- Covenant
    { value = "Interface\\Covenant\\Covenant-BarFill", text = "Blizzard - Covenant Bar" },

    -- OrderHall
    { value = "Interface\\OrderHall\\OrderHall-BarFill", text = "Blizzard - Order Hall Bar" },

    -- Soulbinds
    { value = "Interface\\Soulbinds\\Soulbinds-BarFill", text = "Blizzard - Soulbinds Bar" },

    -- Collections
    { value = "Interface\\Collections\\Collections-BarFill", text = "Blizzard - Collections Bar" },

    -- BattlePet
    { value = "Interface\\BattlePet\\BattlePet-BarFill", text = "Blizzard - Battle Pet Bar" },

    -- Mounts
    { value = "Interface\\Mounts\\Mounts-BarFill", text = "Blizzard - Mount Bar" },

    -- Archaeology
    { value = "Interface\\Archaeology\\Archaeology-BarFill", text = "Blizzard - Archaeology Bar" },

    -- Garrison
    { value = "Interface\\Garrison\\Garrison-BarFill", text = "Blizzard - Garrison Bar" },

    -- Calendar
    { value = "Interface\\Calendar\\Calendar-BarFill", text = "Blizzard - Calendar Bar" },

    -- MailFrame
    { value = "Interface\\MailFrame\\Mail-BarFill", text = "Blizzard - Mail Bar" },

    -- MacroFrame
    { value = "Interface\\MacroFrame\\Macro-BarFill", text = "Blizzard - Macro Bar" },

    -- GlyphFrame
    { value = "Interface\\GlyphFrame\\Glyph-BarFill", text = "Blizzard - Glyph Bar" },

    -- Store
    { value = "Interface\\Store\\Store-BarFill", text = "Blizzard - Store Bar" },

    -- Stable
    { value = "Interface\\Stable\\Stable-BarFill", text = "Blizzard - Stable Bar" },

    -- Vehicle
    { value = "Interface\\Vehicle\\Vehicle-BarFill", text = "Blizzard - Vehicle Bar" },

    -- LossOfControl
    { value = "Interface\\LossOfControl\\LOC-BarFill", text = "Blizzard - Loss of Control Bar" },

    -- Platform / Minigame
    { value = "Interface\\Platform\\Platform-BarFill", text = "Blizzard - Platform Bar" },

    -- PetBattle
    { value = "Interface\\PetBattle\\PetBattle-XP-Bar", text = "Blizzard - Pet Battle XP" },

    -- BarberShop
    { value = "Interface\\BarberShop\\Barber-BarFill", text = "Blizzard - Barber Bar" },

    -- LFGuild
    { value = "Interface\\LFGuild\\LFGuild-BarFill", text = "Blizzard - LF Guild Bar" },

    -- GMChat
    { value = "Interface\\GMChat\\GM-BarFill", text = "Blizzard - GM Chat Bar" },

    -- Buttons
    { value = "Interface\\Buttons\\WHITE8X8", text = "Blizzard - Solid" },
}

-- ============================================================================
-- BACKGROUND TEXTURES (bgFile)
-- ============================================================================
TT.builtinTooltipBackgrounds = {

    -- DialogFrame
    { value = "Interface\\DialogFrame\\UI-DialogBox-Background", text = "Blizzard - Dialog Background" },
    { value = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark", text = "Blizzard - Dialog Background Dark" },
    { value = "Interface\\DialogFrame\\UI-DialogBox-Gold-Background", text = "Blizzard - Dialog Background Gold" },
    { value = "Interface\\DialogFrame\\UI-DialogBox-Header", text = "Blizzard - Dialog Header" },

    -- FullScreenTextures
    { value = "Interface\\FullScreenTextures\\LowHealth", text = "Blizzard - Low Health" },
    { value = "Interface\\FullScreenTextures\\OutOfControl", text = "Blizzard - Out of Control" },
    { value = "Interface\\FullScreenTextures\\Dead", text = "Blizzard - Dead" },
    { value = "Interface\\FullScreenTextures\\Petrified", text = "Blizzard - Petrified" },

    -- FrameGeneral
    { value = "Interface\\FrameGeneral\\UI-Background-Marble", text = "Blizzard - Marble" },
    { value = "Interface\\FrameGeneral\\UI-Background-Rock", text = "Blizzard - Rock" },
    { value = "Interface\\FrameGeneral\\UI-Background-Chat", text = "Blizzard - Chat Background" },

    -- AchievementFrame
    { value = "Interface\\AchievementFrame\\UI-Achievement-Parchment-Horizontal", text = "Blizzard - Parchment" },
    { value = "Interface\\AchievementFrame\\UI-GuildAchievement-Parchment-Horizontal", text = "Blizzard - Parchment 2" },
    { value = "Interface\\AchievementFrame\\UI-Achievement-Background", text = "Blizzard - Achievement Background" },

    -- TabardFrame
    { value = "Interface\\TabardFrame\\TabardFrameBackground", text = "Blizzard - Tabard Background" },
    { value = "Interface\\TabardFrame\\TabardFrameBackground2", text = "Blizzard - Tabard Background 2" },

    -- Tooltips
    { value = "Interface\\Tooltips\\UI-Tooltip-Background", text = "Blizzard - Tooltip Background" },

    -- CastingBar
    { value = "Interface\\CastingBar\\UI-CastingBar-Background", text = "Blizzard - Casting Bar Background" },

    -- QuestFrame
    { value = "Interface\\QuestFrame\\QuestFrameBackground", text = "Blizzard - Quest Background" },
    { value = "Interface\\QuestFrame\\QuestFrameDetailBG", text = "Blizzard - Quest Detail BG" },
    { value = "Interface\\QuestFrame\\QuestFrameHighlight", text = "Blizzard - Quest Highlight" },

    -- GossipFrame
    { value = "Interface\\GossipFrame\\GossipTitleBackground", text = "Blizzard - Gossip Title" },
    { value = "Interface\\GossipFrame\\GossipFrameBackground", text = "Blizzard - Gossip Background" },

    -- ItemText
    { value = "Interface\\ItemText\\ItemText-Background", text = "Blizzard - Item Page" },

    -- CharacterFrame
    { value = "Interface\\CharacterFrame\\CharacterFrameBackground", text = "Blizzard - Character Background" },

    -- Spellbook
    { value = "Interface\\Spellbook\\SpellbookBackground", text = "Blizzard - Spellbook" },

    -- TradeSkillFrame
    { value = "Interface\\TradeSkillFrame\\TradeSkillBackground", text = "Blizzard - Trade Skill" },

    -- MerchantFrame
    { value = "Interface\\MerchantFrame\\MerchantFrameBackground", text = "Blizzard - Merchant" },

    -- TaxiFrame
    { value = "Interface\\TaxiFrame\\TaxiFrameBackground", text = "Blizzard - Flight Map" },

    -- GameTimeFrame
    { value = "Interface\\GameTimeFrame\\GameTimeFrameBackground", text = "Blizzard - Game Time" },

    -- Minimap
    { value = "Interface\\Minimap\\UI-Minimap-Background", text = "Blizzard - Minimap" },

    -- TutorialFrame
    { value = "Interface\\TutorialFrame\\TutorialFrameBackground", text = "Blizzard - Tutorial" },

    -- EncounterJournal
    { value = "Interface\\EncounterJournal\\EncounterJournal-Background", text = "Blizzard - Encounter Journal BG" },

    -- Collections
    { value = "Interface\\Collections\\Collections-Background", text = "Blizzard - Collections BG" },

    -- Store
    { value = "Interface\\Store\\Store-Background", text = "Blizzard - Store BG" },

    -- OrderHall
    { value = "Interface\\OrderHall\\OrderHall-Background", text = "Blizzard - Order Hall BG" },

    -- Covenant
    { value = "Interface\\Covenant\\Covenant-Background", text = "Blizzard - Covenant BG" },

    -- Artifact
    { value = "Interface\\Artifact\\Artifact-Background", text = "Blizzard - Artifact BG" },

    -- Azerite
    { value = "Interface\\Azerite\\Azerite-Background", text = "Blizzard - Azerite BG" },

    -- Scenario
    { value = "Interface\\Scenario\\Scenario-Background", text = "Blizzard - Scenario BG" },

    -- WorldMap
    { value = "Interface\\WorldMap\\WorldMap-Background", text = "Blizzard - World Map BG" },

    -- MailFrame
    { value = "Interface\\MailFrame\\MailFrame-Background", text = "Blizzard - Mail BG" },

    -- Bank
    { value = "Interface\\Bank\\Bank-Background", text = "Blizzard - Bank BG" },

    -- GuildBank
    { value = "Interface\\GuildBank\\GuildBank-Background", text = "Blizzard - Guild Bank BG" },

    -- GuildFrame
    { value = "Interface\\GuildFrame\\GuildFrame-Background", text = "Blizzard - Guild Frame BG" },

    -- Calendar
    { value = "Interface\\Calendar\\Calendar-Background", text = "Blizzard - Calendar BG" },

    -- AuctionFrame
    { value = "Interface\\AuctionFrame\\AuctionFrame-Background", text = "Blizzard - Auction BG" },

    -- HelpFrame
    { value = "Interface\\HelpFrame\\HelpFrame-Background", text = "Blizzard - Help Frame BG" },

    -- LootFrame
    { value = "Interface\\LootFrame\\LootFrame-Background", text = "Blizzard - Loot Frame BG" },

    -- MacroFrame
    { value = "Interface\\MacroFrame\\MacroFrame-Background", text = "Blizzard - Macro Frame BG" },

    -- OptionsFrame
    { value = "Interface\\OptionsFrame\\OptionsFrame-Background", text = "Blizzard - Options Frame BG" },

    -- PartyFrame
    { value = "Interface\\PartyFrame\\PartyFrame-Background", text = "Blizzard - Party Frame BG" },

    -- PetitionFrame
    { value = "Interface\\PetitionFrame\\PetitionFrame-Background", text = "Blizzard - Petition Frame BG" },

    -- PvPFrame
    { value = "Interface\\PvPFrame\\PvPFrame-Background", text = "Blizzard - PvP Frame BG" },

    -- Stable
    { value = "Interface\\Stable\\Stable-Background", text = "Blizzard - Stable BG" },

    -- Trainer
    { value = "Interface\\Trainer\\Trainer-Background", text = "Blizzard - Trainer BG" },

    -- SocialHub
    { value = "Interface\\SocialHub\\SocialHub-Background", text = "Blizzard - Social Hub BG" },

    -- DungeonFind
    { value = "Interface\\DungeonFind\\DungeonFind-Background", text = "Blizzard - Dungeon Find BG" },

    -- BattlePet
    { value = "Interface\\BattlePet\\BattlePet-Background", text = "Blizzard - Battle Pet BG" },

    -- PetJournal
    { value = "Interface\\PetJournal\\PetJournal-Background", text = "Blizzard - Pet Journal BG" },

    -- Mounts
    { value = "Interface\\Mounts\\Mounts-Background", text = "Blizzard - Mounts BG" },

    -- Archaeology
    { value = "Interface\\Archaeology\\Archaeology-Background", text = "Blizzard - Archaeology BG" },

    -- VoidStorage
    { value = "Interface\\VoidStorage\\VoidStorage-Background", text = "Blizzard - Void Storage BG" },

    -- Splash
    { value = "Interface\\Splash\\Splash-Background", text = "Blizzard - Splash BG" },

    -- Barbershop
    { value = "Interface\\BarberShop\\BarberShop-Background", text = "Blizzard - Barbershop BG" },

    -- BackdropTextures
    { value = "Interface\\BackdropTextures\\UI-Backdrop-Textured", text = "Blizzard - Backdrop Textured" },
    { value = "Interface\\BackdropTextures\\UI-Backdrop-Textured-Blue", text = "Blizzard - Backdrop Textured Blue" },
    { value = "Interface\\BackdropTextures\\UI-Backdrop-Textured-Bronze", text = "Blizzard - Backdrop Textured Bronze" },
    { value = "Interface\\BackdropTextures\\UI-Backdrop-Textured-Gold", text = "Blizzard - Backdrop Textured Gold" },
    { value = "Interface\\BackdropTextures\\UI-Backdrop-Textured-Green", text = "Blizzard - Backdrop Textured Green" },
    { value = "Interface\\BackdropTextures\\UI-Backdrop-Textured-Purple", text = "Blizzard - Backdrop Textured Purple" },
    { value = "Interface\\BackdropTextures\\UI-Backdrop-Textured-Red", text = "Blizzard - Backdrop Textured Red" },
    { value = "Interface\\BackdropTextures\\UI-Backdrop-Textured-Silver", text = "Blizzard - Backdrop Textured Silver" },
    { value = "Interface\\BackdropTextures\\UI-Backdrop-Textured-White", text = "Blizzard - Backdrop Textured White" },
    { value = "Interface\\BackdropTextures\\UI-Backdrop-Dark", text = "Blizzard - Backdrop Dark" },
    { value = "Interface\\BackdropTextures\\UI-Backdrop-Dark-Blue", text = "Blizzard - Backdrop Dark Blue" },
    { value = "Interface\\BackdropTextures\\UI-Backdrop-Dark-Bronze", text = "Blizzard - Backdrop Dark Bronze" },
    { value = "Interface\\BackdropTextures\\UI-Backdrop-Dark-Gold", text = "Blizzard - Backdrop Dark Gold" },
    { value = "Interface\\BackdropTextures\\UI-Backdrop-Dark-Green", text = "Blizzard - Backdrop Dark Green" },
    { value = "Interface\\BackdropTextures\\UI-Backdrop-Dark-Purple", text = "Blizzard - Backdrop Dark Purple" },
    { value = "Interface\\BackdropTextures\\UI-Backdrop-Dark-Red", text = "Blizzard - Backdrop Dark Red" },
    { value = "Interface\\BackdropTextures\\UI-Backdrop-Dark-Silver", text = "Blizzard - Backdrop Dark Silver" },
    { value = "Interface\\BackdropTextures\\UI-Backdrop-Dark-White", text = "Blizzard - Backdrop Dark White" },
    { value = "Interface\\BackdropTextures\\UI-Backdrop-Solid", text = "Blizzard - Backdrop Solid" },

    -- Ornament
    { value = "Interface\\Ornament\\Ornament-Background", text = "Blizzard - Ornament" },

    -- UIWidgets
    { value = "Interface\\UIWidgets\\UIWidget-Background", text = "Blizzard - UI Widget BG" },

    -- ChromieTime
    { value = "Interface\\ChromieTime\\ChromieTime-Background", text = "Blizzard - Chromie Time BG" },

    -- TimeManager
    { value = "Interface\\TimeManager\\TimeManager-Background", text = "Blizzard - Time Manager BG" },

    -- Aidan (Art)
    { value = "Interface\\Aidan\\Aidan-Background", text = "Blizzard - Aidan BG" },

    -- TalkingHead
    { value = "Interface\\TalkingHead\\TalkingHead-Background", text = "Blizzard - Talking Head BG" },

    -- LossOfControl
    { value = "Interface\\LossOfControl\\LOC-Background", text = "Blizzard - Loss of Control BG" },

    -- AdventureMap
    { value = "Interface\\AdventureMap\\AdventureMap-Background", text = "Blizzard - Adventure Map BG" },

    -- Warboard
    { value = "Interface\\Warboard\\Warboard-Background", text = "Blizzard - Warboard BG" },

    -- Garrison
    { value = "Interface\\Garrison\\Garrison-Background", text = "Blizzard - Garrison BG" },
    { value = "Interface\\Garrison\\Garrison-Background2", text = "Blizzard - Garrison BG 2" },

    -- Buttons
    { value = "Interface\\Buttons\\WHITE8X8", text = "Blizzard - Solid" },
}

-- ============================================================================
-- BORDER TEXTURES (edgeFile)
-- ============================================================================
TT.builtinTooltipBorders = {

    { value = "Interface\\None", text = "Blizzard - None" },

    -- AchievementFrame
    { value = "Interface\\AchievementFrame\\UI-Achievement-WoodBorder", text = "Blizzard - Achievement Wood" },
    { value = "Interface\\AchievementFrame\\UI-Achievement-Edge", text = "Blizzard - Achievement Edge" },

    -- Tooltips
    { value = "Interface\\Tooltips\\ChatBubble-Backdrop", text = "Blizzard - Chat Bubble" },
    { value = "Interface\\Tooltips\\UI-Tooltip-Border", text = "Blizzard - Tooltip Border" },

    -- DialogFrame
    { value = "Interface\\DialogFrame\\UI-DialogBox-Border", text = "Blizzard - Dialog Border" },
    { value = "Interface\\DialogFrame\\UI-DialogBox-Gold-Border", text = "Blizzard - Dialog Border Gold" },

    -- CharacterFrame
    { value = "Interface\\CHARACTERFRAME\\UI-Party-Border", text = "Blizzard - Party Border" },
    { value = "Interface\\CharacterFrame\\CharacterFrameBorder", text = "Blizzard - Character Frame Border" },

    -- GuildBankFrame
    { value = "Interface\\GuildBankFrame\\GuildBank-Border", text = "Blizzard - Guild Bank" },

    -- QuestFrame
    { value = "Interface\\QuestFrame\\QuestFrameBorder", text = "Blizzard - Quest Border" },

    -- HelpFrame
    { value = "Interface\\HelpFrame\\HelpFrame-Border", text = "Blizzard - Help Frame" },

    -- TrainingFrame
    { value = "Interface\\TrainingFrame\\TrainingFrame-Border", text = "Blizzard - Training Frame" },

    -- Spellbook
    { value = "Interface\\Spellbook\\SpellbookBorder", text = "Blizzard - Spellbook" },

    -- PetFrame
    { value = "Interface\\PetFrame\\PetFrame-Border", text = "Blizzard - Pet Frame" },

    -- StableFrame
    { value = "Interface\\StableFrame\\StableFrameBorder", text = "Blizzard - Stable Frame" },

    -- EncounterJournal
    { value = "Interface\\EncounterJournal\\EncounterJournal-Border", text = "Blizzard - Encounter Journal Border" },

    -- Collections
    { value = "Interface\\Collections\\Collections-Border", text = "Blizzard - Collections Border" },

    -- Store
    { value = "Interface\\Store\\Store-Border", text = "Blizzard - Store Border" },

    -- OrderHall
    { value = "Interface\\OrderHall\\OrderHall-Border", text = "Blizzard - Order Hall Border" },

    -- Covenant
    { value = "Interface\\Covenant\\Covenant-Border", text = "Blizzard - Covenant Border" },

    -- Artifact
    { value = "Interface\\Artifact\\Artifact-Border", text = "Blizzard - Artifact Border" },

    -- Azerite
    { value = "Interface\\Azerite\\Azerite-Border", text = "Blizzard - Azerite Border" },

    -- Scenario
    { value = "Interface\\Scenario\\Scenario-Border", text = "Blizzard - Scenario Border" },

    -- WorldMap
    { value = "Interface\\WorldMap\\WorldMap-Border", text = "Blizzard - World Map Border" },

    -- MailFrame
    { value = "Interface\\MailFrame\\MailFrame-Border", text = "Blizzard - Mail Frame Border" },

    -- Bank
    { value = "Interface\\Bank\\Bank-Border", text = "Blizzard - Bank Border" },

    -- GuildFrame
    { value = "Interface\\GuildFrame\\GuildFrame-Border", text = "Blizzard - Guild Frame Border" },

    -- Calendar
    { value = "Interface\\Calendar\\Calendar-Border", text = "Blizzard - Calendar Border" },

    -- AuctionFrame
    { value = "Interface\\AuctionFrame\\AuctionFrame-Border", text = "Blizzard - Auction Border" },

    -- LootFrame
    { value = "Interface\\LootFrame\\LootFrame-Border", text = "Blizzard - Loot Frame Border" },

    -- MacroFrame
    { value = "Interface\\MacroFrame\\MacroFrame-Border", text = "Blizzard - Macro Frame Border" },

    -- OptionsFrame
    { value = "Interface\\OptionsFrame\\OptionsFrame-Border", text = "Blizzard - Options Frame Border" },

    -- PartyFrame
    { value = "Interface\\PartyFrame\\PartyFrame-Border", text = "Blizzard - Party Frame Border" },

    -- PetitionFrame
    { value = "Interface\\PetitionFrame\\PetitionFrame-Border", text = "Blizzard - Petition Frame Border" },

    -- PvPFrame
    { value = "Interface\\PvPFrame\\PvPFrame-Border", text = "Blizzard - PvP Frame Border" },

    -- Stable
    { value = "Interface\\Stable\\StableFrame-Border", text = "Blizzard - Stable Frame Border" },

    -- Trainer
    { value = "Interface\\Trainer\\TrainerFrame-Border", text = "Blizzard - Trainer Frame Border" },

    -- DungeonFind
    { value = "Interface\\DungeonFind\\DungeonFind-Border", text = "Blizzard - Dungeon Find Border" },

    -- BattlePet
    { value = "Interface\\BattlePet\\BattlePet-Border", text = "Blizzard - Battle Pet Border" },

    -- PetJournal
    { value = "Interface\\PetJournal\\PetJournal-Border", text = "Blizzard - Pet Journal Border" },

    -- Mounts
    { value = "Interface\\Mounts\\Mounts-Border", text = "Blizzard - Mounts Border" },

    -- Archaeology
    { value = "Interface\\Archaeology\\Archaeology-Border", text = "Blizzard - Archaeology Border" },

    -- VoidStorage
    { value = "Interface\\VoidStorage\\VoidStorage-Border", text = "Blizzard - Void Storage Border" },

    -- Barbershop
    { value = "Interface\\BarberShop\\BarberShop-Border", text = "Blizzard - Barbershop Border" },

    -- BackdropTextures
    { value = "Interface\\BackdropTextures\\UI-Backdrop-Edge", text = "Blizzard - Backdrop Edge" },
    { value = "Interface\\BackdropTextures\\UI-Backdrop-Edge-Blue", text = "Blizzard - Backdrop Edge Blue" },
    { value = "Interface\\BackdropTextures\\UI-Backdrop-Edge-Bronze", text = "Blizzard - Backdrop Edge Bronze" },
    { value = "Interface\\BackdropTextures\\UI-Backdrop-Edge-Gold", text = "Blizzard - Backdrop Edge Gold" },
    { value = "Interface\\BackdropTextures\\UI-Backdrop-Edge-Green", text = "Blizzard - Backdrop Edge Green" },
    { value = "Interface\\BackdropTextures\\UI-Backdrop-Edge-Purple", text = "Blizzard - Backdrop Edge Purple" },
    { value = "Interface\\BackdropTextures\\UI-Backdrop-Edge-Red", text = "Blizzard - Backdrop Edge Red" },
    { value = "Interface\\BackdropTextures\\UI-Backdrop-Edge-Silver", text = "Blizzard - Backdrop Edge Silver" },
    { value = "Interface\\BackdropTextures\\UI-Backdrop-Edge-White", text = "Blizzard - Backdrop Edge White" },

    -- TalkingHead
    { value = "Interface\\TalkingHead\\TalkingHead-Border", text = "Blizzard - Talking Head Border" },

    -- Garrison
    { value = "Interface\\Garrison\\Garrison-Border", text = "Blizzard - Garrison Border" },

    -- Ornament
    { value = "Interface\\Ornament\\Ornament-Border", text = "Blizzard - Ornament Border" },

    -- ChromieTime
    { value = "Interface\\ChromieTime\\ChromieTime-Border", text = "Blizzard - Chromie Time Border" },
}
