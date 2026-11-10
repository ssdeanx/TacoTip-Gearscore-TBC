---
created: 2026-11-10T15:54:31 (UTC -05:00)
tags: []
source: https://wowforeverguides.com/addons/pitfalls
author: Harenil
---

# WoW Forever Addon Pitfalls: 12 AI Mistakes & 4 Beta Traps

> ## Excerpt
>
> HomeAddonsAddon Developer GuidePitfalls WoW Forever Addon Pitfalls: 12 AI Mistakes and 4 Beta Traps Models copy interface 120001 or 11503 where the wiki lists 16001, and they do math on UnitHealth, wh

---

1. [Home](https://wowforeverguides.com/)
2. [Addons](https://wowforeverguides.com/addons)
3. [Addon Developer Guide](https://wowforeverguides.com/addons/developers)
4. Pitfalls

## WoW Forever Addon Pitfalls: 12 AI Mistakes and 4 Beta Traps

Models copy interface 120001 or 11503 where the wiki lists 16001, and they do math on UnitHealth, which came back as a secret number on build 69913.

## Ask Our Sweaty Degenerate AI About Addon Pitfalls

Interface Numbers, Secret Health Math, WOW\_PROJECT\_ID, Combat Log Gaps, Beta Sound Traps & More ?

Anything our guides cover. Answers come from this page and the rest of our guides, with the real values charted and the guide sections linked. It's AI, so check the source before you quote it.

Your question about this page  ![](https://wowforeverguides.com/assets/tools/ask-goblin/goblin-still.webp)

Ask

Try

Addon interface number for ForeverSecret health math in addonsVerifying a fix before shippingCombat log in Forever addonsPlaying sound files in betaWOW\_PROJECT\_ID value on ForeverWhy models default to these mistakesChecking build number and interface

These are mistakes a model can make when a WoW addon prompt does not name the Forever client. Each pairs the line it may emit with the line to write instead. Porting from Retail or another client? Check each API against your target build before shipping.

Wrong interface number

16001

Secret health math

h + 1 fails

WOW\_PROJECT\_ID

18 (Camelot)

Combat log

Reported unavailable

## Twelve Traps

### 0101\. Shipping Interface 120001 or 11503

Models copy Midnight guides or Classic templates. The Warcraft Wiki lists 16001 for the Forever beta. A different number can make the client you are testing flag the addon as out of date.

The AddOn List in Zygor's manual, with the Load out of date AddOns box ticked at top right.<small class="wfg-cite-tip" id="cite-dc82ec17f7" popover=""><span class="tip-cite">Source: <a href="#source-6efc028be6ec" target="_blank" rel="noopener" data-link-purpose="citation">Zygor manual: enabling</a> <code class="source-locator">content.zygorguides.com/support/manual/enabling</code>.</span></small>

It writesCopy It writes

```toc
## Interface: 120001
```

You shipCopy You ship

```toc
## Interface: 16001
```

### 0202\. Branching on `WOW_PROJECT_ID`

On build 1.60.1.69913, `WOW_PROJECT_ID` reportedly returned 1, the Mainline value. The retained October 12 probe on build **70338** instead records **18**, matching Blizzard's `WOW_PROJECT_CAMELOT` constant. A Classic-only branch misses Forever; a catch-all branch can mistake it for another client. Compare the named constant, then check the feature's API.<small class="wfg-cite-tip" id="cite-652ea1b820" popover=""><span class="tip-cite">Source: <a href="https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_ProjectConstants/Camelot/ProjectConstants.lua" target="_blank" rel="noopener noreferrer">Blizzard's Camelot project constants</a>, retained 70338 extract inspected Oct 13, 2026; WFG probe captured Oct 12. The mirror may show a later build.</span></small>

It writesCopy It writes

```lua
if WOW_PROJECT_ID ~= WOW_PROJECT_MAINLINE then
    -- Assumes every non-Mainline client is Classic; 70338 Forever enters here.
end
```

You shipCopy You ship

```lua
local isForever = WOW_PROJECT_CAMELOT ~= nil
    and WOW_PROJECT_ID == WOW_PROJECT_CAMELOT
if isForever then
    ns:UseForeverPath()
    -- Only a feature that reads the preset needs this capability.
    local canReadPreset = C_GameRules
        and type(C_GameRules.GetForeverExperiencePreset) == "function"
    if canReadPreset then
        local preset = C_GameRules.GetForeverExperiencePreset()
        -- Use preset for your optional preset-specific feature.
    end
end
```

The older Warcraft Wiki example combined `WOW_PROJECT_MAINLINE` with `LE_EXPANSION_LEVEL_CURRENT == LE_EXPANSION_CLASSIC`. That first condition is false on the captured 70338 client. The revised snippet is source-checked, not tested in game; `ns:UseForeverPath()` represents your own addon code.

### 0303\. Adding One to UnitHealth

In a test on build 69913, `type(UnitHealth("player"))` prints `number`, yet `h + 1` fails. WoW Forever Builds saw Grid2 throw "attempt to perform arithmetic on a secret number value".

It writesCopy It writes

```lua
local h = UnitHealth("player")
local pct = h / UnitHealthMax("player")
```

You shipCopy You ship

```lua
local bar = ns.healthBar
bar:SetMinMaxValues(0, UnitHealthMax("player"))
bar:SetValue(UnitHealth("player"))
```

This example is not tested in game; check that both setters accept the value on your build.

### 0404\. Printing a Name That Might Be Secret

Warcraft Forever reports that unit and creature names may be secret strings. It also says printing one throws an error and can blank your frame. Check first, then fall back to a value you chose.

It writesCopy It writes

```lua
print("Hello " .. UnitName("player"))
```

You shipCopy You ship

```lua
local name = UnitName("player")
if type(issecretvalue) == "function" and issecretvalue(name) then
    name = "adventurer"
end
print("Hello " .. name)
```

### 0505\. GetSpellInfo and GetItemInfo

Both were missing on build 69913, along with `GetSpellBookItemName` and the old talent globals. `C_Spell.GetSpellInfo` returns one table. `C_Item.GetItemInfo` returns the same list of values as the old global.

It writesCopy It writes

```lua
local name, _, icon = GetSpellInfo(8690)
```

You shipCopy You ship

```lua
local info = C_Spell.GetSpellInfo(8690)
if not info then
    C_Spell.RequestLoadSpellData(8690)
    return
end
local name, icon = info.name, info.iconID
```

### 0606\. A Damage Meter, Politely Disguised

On Midnight, registering the combat log event throws an error. Testers report it unavailable on Forever. Blizzard said Forever includes a built-in damage meter and cooldown manager.

It writesCopy It writes

```lua
frame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
```

You shipCopy You ship

```lua
-- Presentation only. Let the built-in meter count.
frame:RegisterUnitEvent("UNIT_HEALTH", "player")
```

### 0707\. Click-Cast via a Secure Snippet

Secure snippets failed to compile on build 69913. Even if a later build fixes that, Warcraft Forever lists secure attributes on Blizzard unit frames as protected, and `pcall` does not make the failure go away.

It writesCopy It writes

```lua
SecureHandlerWrapScript(button, "OnClick", button, [[
    self:SetAttribute("type", "spell")
]])
```

You shipCopy You ship

```lua
-- Own button, plain script, no secure attribute
-- on a Blizzard unit frame.
button:SetScript("OnClick", function()
    -- open your panel, do not cast for the player
end)
```

### 0808\. SavedVariables at File Scope

SavedVariables are `nil` while your file loads. The client loads saved data after your files run, and it replaces whatever your file set. A default assigned at the top is either overwritten or read too early. Players also reported the beta losing saved data between sessions until build 70009.

It writesCopy It writes

```lua
MyAddonDB = MyAddonDB or { enabled = true }
```

You shipCopy You ship

```lua
function events:ADDON_LOADED(loaded)
    if loaded ~= addonName then return end
    MyAddonDB = MyAddonDB or {}
    if MyAddonDB.enabled == nil then
        MyAddonDB.enabled = true
    end
    ns.db = MyAddonDB
end
```

See the full lifecycle in the [SavedVariables template](https://wowforeverguides.com/addons/code-templates).

### 0909\. Canceling C\_Timer.After

`After` returns nothing. The timer object comes from `NewTimer` or `NewTicker`.

It writesCopy It writes

```lua
local t = C_Timer.After(5, func)
t:Cancel()
```

You shipCopy You ship

```lua
local t = C_Timer.NewTimer(5, func)
t:Cancel()
```

### 1010\. Protected Calls Hidden in Pcall

Warcraft Forever reports that `ChatFrame_OpenChat`, `C_SuperTrack.SetSuperTrackedUserWaypoint` and secure attributes on Blizzard frames fail without a Lua error. The only symptom is an interface-action counter that `/reload` does not reset.

It writesCopy It writes

```lua
pcall(C_SuperTrack.SetSuperTrackedUserWaypoint, true)
```

You shipCopy You ship

```lua
local point = UiMapPoint.CreateFromCoordinates(uiMapID, x, y)
C_Map.SetUserWaypoint(point)
```

`C_Map.SetUserWaypoint` places the pin; the wiki documents `C_SuperTrack.SetSuperTrackedUserWaypoint` as the separate call that tracks it. Warcraft Forever's page, captured September 28, lists that call as protected but names no client build, so retest on yours.

### 1111\. Faction Tests That Lie

Warcraft Forever reports that `UnitIsEnemy` and `UnitCanAttack` mean "attackable right now" on this client, not "other faction": both answer false for an unflagged enemy, in a sanctuary or on another shard. Its secret-value list names `UnitCanAttack`, not `UnitIsEnemy`, as a secret boolean. The report names no build, so retest on yours.

It writesCopy It writes

```lua
if UnitIsEnemy("player", unit) then
```

You shipCopy You ship

```lua
local them = UnitFactionGroup(unit)
local mine = UnitFactionGroup("player")
if them and mine and them ~= mine then
```

### 1212\. Slash Commands That Never Register

The global must be `SLASH_NAME1` and the `SlashCmdList` key must be the same `NAME`, spelled the same way. A local, or a key that does not match, never registers.

It writesCopy It writes

```lua
local SLASH_fb1 = "/fb"
SlashCmdList.fb = function() end
```

You shipCopy You ship

```lua
SLASH_FOREVERBEACON1 = "/fb"
SlashCmdList["FOREVERBEACON"] = function(msg)
end
```

For complete safe bars, combat queues and addon compartments, see the [code templates](https://wowforeverguides.com/addons/code-templates).

## Four More Traps From the Beta

The twelve above cover the biggest breaks. These four are smaller. Traps 13 and 14 are unverified community beta reports from Warcraft Forever. Traps 15 and 16 come from the Warcraft Wiki's Mainline API pages, the UI family Forever runs. They have not been retested on a Forever build.

### 1313\. Playing a Sound File the Classic Way

Warcraft Forever reports that `PlaySoundFile` with a `Sound\Interface\*.ogg` path fails silently on this client. Nothing errors and nothing prints; the sound never plays.

It writesCopy It writes

```lua
PlaySoundFile("Sound\\Interface\\LevelUp.ogg")
```

You shipCopy You ship

```lua
-- Warcraft Wiki, PlaySound: play by SoundKitID, not a file path.
PlaySound(SOUNDKIT.READY_CHECK)
```

The wiki's `PlaySound` page documents playing by SoundKitID or a `SOUNDKIT` key. Warcraft Forever also says to check the master volume before blaming the addon.

### 1414\. Trusting a Nameplate the Instant It Appears

Warcraft Forever reports that `NAME_PLATE_UNIT_ADDED` fires before the unit is populated, and that plate frames carry no `namePlateUnitToken` on this client. Reading the unit in the same handler gets nothing useful.

It writesCopy It writes

```lua
frame:SetScript("OnEvent", function(self, event, unit)
    self.name:SetText(UnitName(unit))
end)
```

You shipCopy You ship

```lua
frame:SetScript("OnEvent", function(self, event, unit)
    C_Timer.After(0, function()
        self.name:SetText(UnitName(unit))
    end)
end)
-- Or sweep nameplate1..nameplate40 yourself a moment later.
```

### 1515\. Assuming a Metadata Lookup Fails Quietly

The wiki says `C_AddOns.GetAddOnMetadata`, unlike the old global, raises an "Invalid AddOn name" error when the addon does not exist. A model that ports the old call and keeps its `nil` check would stop the file on a missing optional dependency. Test the guarded pattern below on your Forever build.

It writesCopy It writes

```lua
local ver = C_AddOns.GetAddOnMetadata("SomeOtherAddon", "Version")
if not ver then return end
```

You shipCopy You ship

```lua
local ok, ver = pcall(C_AddOns.GetAddOnMetadata, "SomeOtherAddon", "Version")
if not ok or not ver then return end
```

### 1616\. Wiring the Settings Panel Through the Old Globals

The wiki dates the Settings API rewrite to patch 10.0.0, with more breaking changes in 11.0.2. Its documented pattern registers a category and opens it through `Settings`, not the older `InterfaceOptionsFrame_OpenToCategory` that Classic Era templates call.

It writesCopy It writes

```lua
InterfaceOptionsFrame_OpenToCategory(MyAddonOptionsPanel)
```

You shipCopy You ship

```lua
local category = Settings.RegisterVerticalLayoutCategory("My Addon")
Settings.RegisterAddOnCategory(category)
-- Later, from a slash command:
Settings.OpenToCategory(category:GetID())
```

Register the category once at load, then open it from a slash command or an addon compartment entry like the one in the [Forever Beacon sample addon](https://wowforeverguides.com/addons/forever-beacon).

## Why Models Default to These Mistakes

These examples show a risk, not a measured error rate. Without the target client named, a model asked for a health bar may reach for arithmetic, and one asked for options may call a panel API from an older interface.

Kenneth Henseler goes through four errors where an AI said a function did not exist when it did, September 25, 2026.

The fix is context, not a cleverer prompt. Tell the model the interface number, the project ID and the APIs the beta reports, and start from the [prompt templates for Forever addons](https://wowforeverguides.com/addons/ai-prompts).

## Verifying a Fix Before You Ship It

None of these sixteen fixes is guaranteed to survive the next beta build. Retest each one on the build you are running.

Start with `/run print(select(2, GetBuildInfo()), select(4, GetBuildInfo()))`, which prints the build and the interface number. Then run WoW Forever Builds' health test from trap 03: `/run local h = UnitHealth("player"); print(type(h), pcall(function() return h + 1 end))`. On build 69913 it printed `number false`: `pcall` caught an error, so the addition was refused. If it prints `true`, that read is no longer secret on your build. That result covers only this test; test the status bar example separately.

For trap 08, log out fully and back in, not just `/reload`, and check that your saved table survived. Players reported a SavedVariables restore bug from Sep 21, 2026, and one player said build 70009 fixed it on Sep 25. Blizzard hasn't confirmed a fix.

Test trap 11 against an unflagged enemy player, in a sanctuary or on another shard. Warcraft Forever reports that `UnitIsEnemy` and `UnitCanAttack` both return false there.

For the protected calls in traps 07 and 10, watch the AddOns panel's interface-action counter rather than `pcall`'s return value. `/reload` does not reset that counter, so restart the client before you retest, or an old count will make a working fix look broken.

Note the build number next to any fix you rely on, the way the [API cheat sheet](https://wowforeverguides.com/addons/api-cheatsheet) marks rows observed on build 69913. A trap fixed on one build can reopen on the next.

## Key Facts

- Wrong interface number <small data-change="changed">Changed</small>Models copy 120001 or 11503; the wiki lists 16001 for the Forever beta
- Secret health math <small data-change="changed">Changed</small>type() says number, but h + 1 fails; pcall returns false instead of a sum
- WOW\_PROJECT\_ID <small data-change="changed">Changed</small>18 (WOW\_PROJECT\_CAMELOT) in the October 12 WFG probe on build 70338; older build 69913 reported 1<small>Classic: Classic Era returns 2 (WOW_PROJECT_CLASSIC).</small>
- Combat log <small data-change="removed">Removed</small>Registering COMBAT\_LOG\_EVENT\_UNFILTERED errors on Midnight; reported unavailable on Forever

## Sources

1. [What the WoW Forever beta breaks for addons: secret health values, dead secure snippets, new APIs](https://wowforeverbuilds.com/news/what-the-wow-forever-beta-breaks-for-addons-secret-health-values-dead-secure-sni)WoW Forever BuildsSep 18, 2026
2. [Addons](https://warcraftforever.games/addons)Warcraft Forever
3. [TOC format](https://warcraft.wiki.gg/wiki/TOC_format)Warcraft Wiki
4. [Secret Values](https://warcraft.wiki.gg/wiki/Secret_Values)Warcraft Wiki
5. [Patch 12.0.0/API changes](https://warcraft.wiki.gg/wiki/Patch_12.0.0/API_changes)Warcraft Wiki
6. [C\_Item.GetItemInfo](https://warcraft.wiki.gg/wiki/API_C_Item.GetItemInfo)Warcraft Wiki
7. [Saving variables between game sessions](https://warcraft.wiki.gg/wiki/Saving_variables_between_game_sessions)Warcraft Wiki
8. [WOWF Beta: Addon SavedVariables appear to write correctly to disk but are not restored at startup](https://us.forums.blizzard.com/en/wow/t/wowf-beta-addon-savedvariables-appear-to-write-correctly-to-disk-but-are-not-restored-at-startup/2356559)World of Warcraft Forums (player bug report)Sep 21, 2026
9. [C\_Map.SetUserWaypoint](https://warcraft.wiki.gg/wiki/API_C_Map.SetUserWaypoint)Warcraft Wiki
10. [C\_AddOns.GetAddOnMetadata](https://warcraft.wiki.gg/wiki/API_C_AddOns.GetAddOnMetadata)Warcraft Wiki
11. [Settings API](https://warcraft.wiki.gg/wiki/Settings_API)Warcraft Wiki
12. [PlaySound](https://warcraft.wiki.gg/wiki/API_PlaySound)Warcraft Wiki
13. [RXPGuides releases](https://github.com/RestedXP/RXPGuides/releases)RestedXP (GitHub)
14. [Zygor's World of Warcraft Forever guides launching this November](https://zygorguides.com/blog/zygors-world-of-warcraft-forever-guides-launching-this-november/ref/Decarebia/?campaign=wowforeverguides.com)Zygor GuidesSep 15, 2026
15. [Blizzard client source: ProjectConstants.lua (retained build 70338; mirror may change)](https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_ProjectConstants/Camelot/ProjectConstants.lua)Blizzard Entertainment (source mirrored by Gethe)
16. [Zygor manual: enabling](https://content.zygorguides.com/support/manual/enabling)

## Units and Secrets

- Blizzard said Midnight's secret values are active on Forever. Doing math on a secret value, or comparing one, throws an error:

Call Can be secret Safe use
UnitHealth / UnitHealthMax Yes, number StatusBar:SetMinMaxValues and StatusBar:SetValue
UnitName / creature names Yes, string Show only after issecretvalue is false
UnitCanAttack / UnitExists Yes, boolean Do not branch until the guard says plain
UnitIsEnemy Often the wrong question Means attackable now, not opposite faction
UnitFactionGroup Check before compare them ~= mine is the faction test
The "can be secret" column for names and booleans comes from Warcraft Forever's beta notes. Health comes from WoW Forever Builds' test. Run this guard before you branch on a value or display it:

Guard.lua
CopyGuard.lua
local function Sealed(value)
    return type(issecretvalue) == "function" and issecretvalue(value)
end
The code templates and the Forever Beacon sample have guarded status-bar examples. Test them on your current build.

## Events Instead of the Combat Log

- On Midnight, registering COMBAT_LOG_EVENT_UNFILTERED throws an error (Warcraft Wiki, Patch 12.0.0 API changes). Warcraft Forever reports that the combat log reader is unavailable on Forever. Register unit events instead:

You wanted Register
Player health RegisterUnitEvent("UNIT_HEALTH", "player")
Power UNIT_POWER_UPDATE
A cast started or finished UNIT_SPELLCAST_START,_STOP, _SUCCEEDED,_FAILED, _INTERRUPTED
Auras Let Blizzard's aura frames draw them. UNIT_AURA is not a license to read aura data in combat.
Entering and leaving combat PLAYER_REGEN_DISABLED and PLAYER_REGEN_ENABLED
A boss pull ENCOUNTER_START and ENCOUNTER_END, if the encounter fires them
Zone changes ZONE_CHANGED_NEW_AREA, PLAYER_ENTERING_WORLD

SavedVariables
Declare the table in the TOC: ## SavedVariables: BeaconNotesDB. The name is a global because the client fills it in after your files run. Touch it only in ADDON_LOADED, and merge default keys so you never overwrite a player's settings.

SavedVariables.lua
CopySavedVariables.lua
local addonName, ns = ...
local defaults = { scale = 1, locked = false }

local events = {}
function events:ADDON_LOADED(loaded)
    if loaded ~= addonName then return end
    BeaconNotesDB = BeaconNotesDB or {}
    local db = BeaconNotesDB
    for key, value in pairs(defaults) do
        if db[key] == nil then db[key] = value end
    end
    ns.db = db
end

local frame = CreateFrame("Frame")
frame:SetScript("OnEvent", function(self, event, ...)
    if events[event] then events[event](self, ...) end
end)
frame:RegisterEvent("ADDON_LOADED")
Don't set BeaconNotesDB = BeaconNotesDB or {} at file scope. It is trap 08 in the common AI addon pitfalls.

## Delay Work Without an OnUpdate Script

- C_Timer.After schedules a one-shot callback. A Blizzard post quoted on the wiki says the timer system only does work when a timer is created or destroyed, while an OnUpdate handler costs a Lua call every rendered frame.

Debounce.lua
CopyDebounce.lua
local pendingSave = false

local function ScheduleSave()
    if pendingSave then return end
    pendingSave = true
    C_Timer.After(2, function()
        pendingSave = false
        -- update an in-memory table or refresh a preview here
    end)
end
Use this to debounce follow-up work after a setting changes, such as updating an in-memory table or refreshing a preview. The timer does not write SavedVariables to disk; the client persists declared variables on logout or UI reload.
