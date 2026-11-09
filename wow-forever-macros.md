# WoW Forever Macro Cheatsheet (nobody174 style)

Copy/paste macros for Priest, Shaman, Paladin, Warlock, Hunter and Warrior. Each class has a **Shared** section (every spec uses it) plus spec-only extras.

## Patterns

**Damage (Priest — target-of-target aware)**
```
#showtooltip SPELL
/cast [@targettarget, harm, exists][harm] SPELL
```

**Damage (every other class)**
```
#showtooltip SPELL
/cast [harm] SPELL
```

**Mouseover heal / utility (adds self fallback)**
```
#showtooltip SPELL
/cast [@mouseover, help, exists][help][@player] SPELL
```

**Friend-or-foe, e.g. Dispel Magic (adds self fallback)**
```
#showtooltip SPELL
/cast [@mouseover, exists][exists][@player] SPELL
```

**Buffs (adds self fallback)**
```
#showtooltip SPELL
/cast [@mouseover, help, exists][help][@player] SPELL
```

**Spam-safe channel**
```
#showtooltip SPELL
/cast [@targettarget, harm, exists, nochanneling][harm, nochanneling] SPELL
```

**Wand**
```
#showtooltip Shoot
/cast [@targettarget, harm, exists, nochanneling:Shoot] Shoot
/cast [harm, nochanneling:Shoot] Shoot
```

## Notes

- Spells without a rank cast your highest rank automatically.
- Buff, heal/utility and friend-or-foe macros all add `[@player]` as a last fallback, so they hit you instead of doing nothing with no target. Delete it if you want the strict targeting-only style.
- Item macros (`/use ...`) need the item name edited to the rank you carry.
- WoW Forever changes some classes/systems; if a spell name is renamed or missing in beta, swap the name and keep the pattern.
- Macro limit is 255 characters; every macro here fits.

## Universal (all classes)

### Targeting helpers

**Smart target enemy** (`SmartTarget`) — Only grabs a new enemy if you have no live hostile target.
```
/targetenemy [noharm][dead]
```

**Grab TT (take the mob off your friend)** (`GrabTT`)
```
/target [@targettarget, harm, exists]
```

**Assist mouseover / friendly target** (`Assist@`)
```
/assist [@mouseover, help, exists][help]
```

**Clear dead target** (`ClearDead`)
```
/cleartarget [dead]
```

**Skull mark mouseover / target** (`SkullMark`) — 8 = skull, 7 = cross, 5 = moon, 6 = square. Uses the full /targetmarker name, not the /tm shorthand — the ThreatMaster addon claims /tm for itself, which silently breaks this macro if you use the short form.
```
/targetmarker [@mouseover, exists][] 8
```

### Focus

**Set focus (mouseover first)** (`SetFocus`)
```
/focus [@mouseover, exists][]
```

**Clear focus** (`ClearFocus`)
```
/clearfocus
```

**Target focus** (`TargetFoc`)
```
/target focus
```

**Assist focus (set tank as focus)** (`AssistFoc`)
```
/assist focus
```

### Misc / UI

**Zoom out more** (`Zoom`) — Raises the max camera zoom-out distance beyond the default cap.
```
/console cameraDistanceMaxZoomFactor 4
```

**Hide guild names** (`HideGuild`) — Removes guild tags from nameplates and unit frames.
```
/console UnitNamePlayerGuild 0
```

**Hide PvP titles** (`HidePvP`) — Removes PvP rank titles from nameplates and unit frames.
```
/console UnitNamePlayerPVPTitle 0
```

**Weapon swap: 1H+offhand ↔ 2H** (`WeaponSwap`) — Swap the item names for your own gear. Toggles between 1H+offhand and 2H each press — slot 16 = main hand, 17 = off hand/shield.
```
/equipslot 16 Durgen's Crescent Axe
/equipslot 17 Veteran Shield
/equipslot 16 Ironforge Greathammer
```

## Priest

### Priest — Shared (all specs)

#### Damage / offensive

**Shadow Word: Pain** (`SWP`)
```
#showtooltip Shadow Word: Pain
/cast [@targettarget, harm, exists][harm] Shadow Word: Pain
```

**Mind Blast** (`MBlast`)
```
#showtooltip Mind Blast
/cast [@targettarget, harm, exists][harm] Mind Blast
```

**Smite** (`Smite`)
```
#showtooltip Smite
/cast [@targettarget, harm, exists][harm] Smite
```

**Holy Fire** (`HFire`)
```
#showtooltip Holy Fire
/cast [@targettarget, harm, exists][harm] Holy Fire
```

**Mana Burn** (`ManaBurn`)
```
#showtooltip Mana Burn
/cast [@targettarget, harm, exists][harm] Mana Burn
```

#### Mouseover healing / utility

**Flash Heal** (`FHeal`)
```
#showtooltip Flash Heal
/cast [@mouseover, help, exists][help][@player] Flash Heal
```

**Heal** (`Heal`)
```
#showtooltip Heal
/cast [@mouseover, help, exists][help][@player] Heal
```

**Greater Heal** (`GHeal`)
```
#showtooltip Greater Heal
/cast [@mouseover, help, exists][help][@player] Greater Heal
```

**Lesser Heal** (`LHeal`)
```
#showtooltip Lesser Heal
/cast [@mouseover, help, exists][help][@player] Lesser Heal
```

**Renew** (`Renew`)
```
#showtooltip Renew
/cast [@mouseover, help, exists][help][@player] Renew
```

**Power Word: Shield** (`PWS`)
```
#showtooltip Power Word: Shield
/cast [@mouseover, help, exists][help][@player] Power Word: Shield
```

**Resurrection** (`Rez`)
```
#showtooltip Resurrection
/cast [@mouseover, help, exists][help][@player] Resurrection
```

#### Cleanse / dispel

**Dispel Magic (friend or foe)** (`Dispel`)
```
#showtooltip Dispel Magic
/cast [@mouseover, exists][exists][@player] Dispel Magic
```

**Cure Disease** (`CureDisease`)
```
#showtooltip Cure Disease
/cast [@mouseover, help, exists][help][@player] Cure Disease
```

**Abolish Disease** (`AbolishDis`)
```
#showtooltip Abolish Disease
/cast [@mouseover, help, exists][help][@player] Abolish Disease
```

#### Wand / auto-attack

**Wand (spam-safe)** (`Wand`)
```
#showtooltip Shoot
/cast [@targettarget, harm, exists, nochanneling:Shoot] Shoot
/cast [harm, nochanneling:Shoot] Shoot
```

#### Buffs

**Power Word: Fortitude** (`PWFort`)
```
#showtooltip Power Word: Fortitude
/cast [@mouseover, help, exists][help][@player] Power Word: Fortitude
```

**Prayer of Fortitude** (`PoFort`)
```
#showtooltip Prayer of Fortitude
/cast [@mouseover, help, exists][help][@player] Prayer of Fortitude
```

**Shadow Protection** (`ShadowProt`)
```
#showtooltip Shadow Protection
/cast [@mouseover, help, exists][help][@player] Shadow Protection
```

**Levitate** (`Levitate`)
```
#showtooltip Levitate
/cast [@mouseover, help, exists][help][@player] Levitate
```

**Fear Ward** (`FearWard`) — Racial/availability may differ in Forever.
```
#showtooltip Fear Ward
/cast [@mouseover, help, exists][help][@player] Fear Ward
```

#### Panic / defensive

**Shield self** (`PWS me`)
```
#showtooltip Power Word: Shield
/cast [@player] Power Word: Shield
```

#### Focus

**Shackle Undead on focus** (`Shackle F`)
```
#showtooltip Shackle Undead
/cast [@focus, harm, exists][harm] Shackle Undead
```

**Mind Control on focus** (`MindCtrl F`)
```
#showtooltip Mind Control
/cast [@focus, harm, exists][harm] Mind Control
```

### Priest — Shadow

#### Damage / offensive

**Mind Flay (spam-safe)** (`MFlay`) — Won't clip an active channel.
```
#showtooltip Mind Flay
/cast [@targettarget, harm, exists, nochanneling][harm, nochanneling] Mind Flay
```

**Vampiric Embrace** (`VampEmb`)
```
#showtooltip Vampiric Embrace
/cast [@targettarget, harm, exists][harm] Vampiric Embrace
```

**Silence (interrupt)** (`Silence`) — Clears your current cast first so the interrupt fires instantly.
```
#showtooltip Silence
/stopcasting
/cast [@targettarget, harm, exists][harm] Silence
```

**Devouring Plague** (`DevPlague`) — Racial priest spell.
```
#showtooltip Devouring Plague
/cast [@targettarget, harm, exists][harm] Devouring Plague
```

#### Buffs

**Shadowform (no cancel)** (`Shadowform`) — Won't drop you out of form if pressed again.
```
#showtooltip Shadowform
/cast [noform] Shadowform
```

#### Focus

**Silence focus** (`Silence F`) — Clears your current cast first so the interrupt fires instantly.
```
#showtooltip Silence
/stopcasting
/cast [@focus, harm, exists][harm] Silence
```

### Priest — Holy

#### Mouseover healing / utility

**Inner Focus + Greater Heal** (`IF+GHeal`) — While the first spell is on cooldown this button does nothing: use the plain spell button then.
```
#showtooltip Greater Heal
/cast Inner Focus
/cast [@mouseover, help, exists][help][@player] Greater Heal
```

**Prayer of Mending** (`PoM`) — New in Forever. Heals, then jumps to another group member when they take damage.
```
#showtooltip Prayer of Mending
/cast [@mouseover, help, exists][help][@player] Prayer of Mending
```

### Priest — Discipline

#### Mouseover healing / utility

**Power Infusion** (`PowerInf`)
```
#showtooltip Power Infusion
/cast [@mouseover, help, exists][help][@player] Power Infusion
```

**Penance (friend or foe)** (`Penance`) — New in Forever. Heals a friendly mouseover/target, damages an enemy one.
```
#showtooltip Penance
/cast [@mouseover, exists][exists][@player] Penance
```

#### Buffs

**Divine Spirit** (`DivSpirit`)
```
#showtooltip Divine Spirit
/cast [@mouseover, help, exists][help][@player] Divine Spirit
```

## Warlock

### Warlock — Shared (all specs)

#### Damage / offensive

**Shadow Bolt (target / target's target)** (`ShadowBolt`) — Casts on your target if it is a living enemy; if your target is friendly (a tank, say), on what that target is attacking. No mouseover.
```
#showtooltip Shadow Bolt
/cast [harm, nodead][@targettarget, harm, nodead] Shadow Bolt
```

**Corruption mouseover** (`Corruption`) — Mouseover enemy first, then your enemy target, then your friendly target's enemy target. Nothing happens (no error) if none of them is a living enemy.
```
#showtooltip Corruption
/cast [@mouseover, harm, nodead][harm, nodead][@targettarget, harm, nodead] Corruption
```

**Bane of Agony mouseover** (`BaneAgony`) — Same targeting as Corruption mouseover. Called Bane of Agony in Forever (Curse of Agony in Classic).
```
#showtooltip Bane of Agony
/cast [@mouseover, harm, nodead][harm, nodead][@targettarget, harm, nodead] Bane of Agony
```

**Drain Life (spam-safe)** (`DrainLife`)
```
#showtooltip Drain Life
/cast [@targettarget, harm, exists, nochanneling][harm, nochanneling] Drain Life
```

**Drain Soul (spam-safe)** (`DrainSoul`)
```
#showtooltip Drain Soul
/cast [@targettarget, harm, exists, nochanneling][harm, nochanneling] Drain Soul
```

**Drain Mana (spam-safe)** (`DrainMana`)
```
#showtooltip Drain Mana
/cast [@targettarget, harm, exists, nochanneling][harm, nochanneling] Drain Mana
```

#### Mouseover healing / utility

**Unending Breath** (`UnendBreath`)
```
#showtooltip Unending Breath
/cast [@mouseover, help, exists][help][@player] Unending Breath
```

**Detect Invisibility** (`DetectInv`)
```
#showtooltip Detect Invisibility
/cast [@mouseover, help, exists][help][@player] Detect Invisibility
```

**Soulstone mouseover** (`Soulstone`) — Swap item name to your soulstone rank.
```
/use [@mouseover, help, exists][help] Major Soulstone
```

#### Cleanse / dispel

**Devour Magic (Felhunter)** (`DevourMagic`)
```
#showtooltip Devour Magic
/cast [@mouseover, help, exists][help][@player] Devour Magic
```

#### Wand / auto-attack

**Wand (spam-safe)** (`Wand`)
```
#showtooltip Shoot
/cast [@targettarget, harm, exists, nochanneling:Shoot] Shoot
/cast [harm, nochanneling:Shoot] Shoot
```

#### Class QoL

**Pet attack TT / target** (`PetAtk`)
```
/petattack [@targettarget, harm, exists][harm]
```

**Pet attack mouseover** (`PetAtkMO`) — Mouseover enemy first, then your enemy target, then your friendly target's enemy target. No #showtooltip: /petattack is not a spell, so it would show a red ?. Pick the icon yourself in the macro window: the claw icon from the pet bar's Attack button (Ability_GhoulFrenzy).
```
/petattack [@mouseover, harm, nodead][harm, nodead][@targettarget, harm, nodead]
```

#### Focus

**Fear focus** (`Fear F`)
```
#showtooltip Fear
/cast [@focus, harm, exists][harm] Fear
```

**Banish focus** (`Banish F`)
```
#showtooltip Banish
/cast [@focus, harm, exists][harm] Banish
```

**Seduction focus** (`Seduce F`)
```
#showtooltip Seduction
/cast [@focus, harm, exists][harm] Seduction
```

**Spell Lock focus** (`SpellLock F`)
```
#showtooltip Spell Lock
/cast [@focus, harm, exists][harm] Spell Lock
```

**Enslave Demon focus** (`Enslave F`)
```
#showtooltip Enslave Demon
/cast [@focus, harm, exists][harm] Enslave Demon
```

**Bane of Havoc focus** (`BoHavoc F`) — New in Forever. Put it on a second mob (focus), then nuke your target: part of your damage is copied onto the focus.
```
#showtooltip Bane of Havoc
/cast [@focus, harm, exists][harm] Bane of Havoc
```

### Warlock — Affliction

#### Damage / offensive

**Wrack (spam-safe)** (`Wrack`) — New in Forever. Channeled drain that makes the target take more Shadow DoT damage.
```
#showtooltip Wrack
/cast [@targettarget, harm, exists, nochanneling][harm, nochanneling] Wrack
```

**Amplify Curse + Bane of Agony** (`AmpCurse`) — While the first spell is on cooldown this button does nothing: use the plain spell button then.
```
#showtooltip Bane of Agony
/cast Amplify Curse
/cast [harm] Bane of Agony
```

**DoT sequence (press to roll dots)** (`DoTSeq`)
```
#showtooltip Corruption
/castsequence [harm] reset=target Corruption, Bane of Agony, Siphon Life, Immolate
```

### Warlock — Demonology

#### Class QoL

**Fel Domination + Felhunter** (`FelDom+FH`) — While the first spell is on cooldown this button does nothing: use the plain spell button then.
```
#showtooltip Summon Felhunter
/cast Fel Domination
/cast Summon Felhunter
```

**Fel Domination + Voidwalker** (`FelDom+VW`) — While the first spell is on cooldown this button does nothing: use the plain spell button then.
```
#showtooltip Summon Voidwalker
/cast Fel Domination
/cast Summon Voidwalker
```

### Warlock — Destruction

#### Damage / offensive

**Immolate > Conflagrate** (`Immo>Conflag`)
```
#showtooltip Immolate
/castsequence [harm] reset=target/10 Immolate, Conflagrate
```

## Mage

### Mage — Shared (all specs)

#### Damage / offensive

**Arcane Missiles (spam-safe)** (`ArcMissiles`)
```
#showtooltip Arcane Missiles
/cast [@targettarget, harm, exists, nochanneling][harm, nochanneling] Arcane Missiles
```

**Frost Nova** (`FrostNova`) — Clears your current cast first so the root fires instantly.
```
#showtooltip Frost Nova
/stopcasting
/cast [harm] Frost Nova
```

**Counterspell (interrupt)** (`CSpell`) — Clears your current cast first so the interrupt fires instantly.
```
#showtooltip Counterspell
/stopcasting
/cast [harm] Counterspell
```

**Polymorph + Diamond mark** (`Poly+Mark`) — Marks the sheep target with a diamond so the group knows not to break it. Uses the full /targetmarker name, not /tm — the ThreatMaster addon claims /tm for itself, which silently breaks this macro if you use the short form.
```
#showtooltip Polymorph
/targetmarker [harm] 3
/cast [harm] Polymorph
```

#### Cleanse / dispel

**Remove Lesser Curse (friend or foe)** (`RemCurse@`)
```
#showtooltip Remove Lesser Curse
/cast [@mouseover, exists][exists][@player] Remove Lesser Curse
```

#### Buffs

**Arcane Intellect** (`ArcInt`)
```
#showtooltip Arcane Intellect
/cast [@mouseover, help, exists][help][@player] Arcane Intellect
```

**Dampen Magic** (`DampenMagic`)
```
#showtooltip Dampen Magic
/cast [@mouseover, help, exists][help][@player] Dampen Magic
```

**Amplify Magic** (`AmpMagic`)
```
#showtooltip Amplify Magic
/cast [@mouseover, help, exists][help][@player] Amplify Magic
```

#### Panic / defensive

**Ice Block (press again to cancel)** (`IceBlock`) — First press casts Ice Block, second press cancels it early.
```
#showtooltip Ice Block
/cancelaura Ice Block
/cast Ice Block
```

#### Focus

**Counterspell focus** (`CSpell F`) — Clears your current cast first so the interrupt fires instantly.
```
#showtooltip Counterspell
/stopcasting
/cast [@focus, harm, exists][harm] Counterspell
```

**Polymorph focus** (`Poly F`)
```
#showtooltip Polymorph
/cast [@focus, harm, exists][harm] Polymorph
```

### Mage — Arcane

#### Damage / offensive

**Arcane Power + Arcane Missiles** (`APower+AMiss`) — While the first spell is on cooldown this button does nothing: use the plain spell button then.
```
#showtooltip Arcane Missiles
/cast Arcane Power
/cast [harm] Arcane Missiles
```

**Presence of Mind + Frostbolt** (`PoM+Frost`) — Instant-cast next spell. While the first spell is on cooldown this button does nothing: use the plain spell button then.
```
#showtooltip Frostbolt
/cast Presence of Mind
/cast [harm] Frostbolt
```

**Presence of Mind + Pyroblast** (`PoM+Pyro`) — The classic burst combo for Arcane/Fire hybrids: instant Pyroblast. While the first spell is on cooldown this button does nothing: use the plain spell button then.
```
#showtooltip Pyroblast
/cast Presence of Mind
/cast [harm] Pyroblast
```

## Rogue

### Rogue — Shared (all specs)

#### Damage / offensive

**Sinister Strike** (`SinStrike`)
```
#showtooltip Sinister Strike
/startattack [harm]
/cast [harm] Sinister Strike
```

**Backstab** (`Backstab`)
```
#showtooltip Backstab
/startattack [harm]
/cast [harm] Backstab
```

**Eviscerate** (`Evisc`)
```
#showtooltip Eviscerate
/startattack [harm]
/cast [harm] Eviscerate
```

**Gouge (mouseover)** (`Gouge@`)
```
#showtooltip Gouge
/cast [@mouseover, harm, nodead][harm, nodead] Gouge
```

**Kidney Shot** (`KidneyShot`)
```
#showtooltip Kidney Shot
/startattack [harm]
/cast [harm] Kidney Shot
```

**Rupture** (`Rupture`)
```
#showtooltip Rupture
/startattack [harm]
/cast [harm] Rupture
```

**Garrote** (`Garrote`) — Requires stealth.
```
#showtooltip Garrote
/startattack [harm]
/cast [harm] Garrote
```

**Ambush** (`Ambush`) — Requires stealth.
```
#showtooltip Ambush
/startattack [harm]
/cast [harm] Ambush
```

**Cheap Shot** (`CheapShot`) — Requires stealth. Classic stunlock opener.
```
#showtooltip Cheap Shot
/startattack [harm]
/cast [harm] Cheap Shot
```

**Kick (mouseover)** (`Kick@`) — Clears your current cast first so the interrupt fires instantly.
```
#showtooltip Kick
/stopcasting
/cast [@mouseover, harm, nodead][harm, nodead] Kick
```

#### Wand / auto-attack

**Ranged weapon (Bow/Gun/Crossbow/Thrown)** (`Ranged`) — One button for whatever ranged weapon you have equipped.
```
#showtooltip
/cast [equipped:Bows] Shoot Bow; [equipped:Guns] Shoot Gun; [equipped:Crossbows] Shoot Crossbow; [equipped:Thrown] Throw
```

#### Panic / defensive

**Blind (mouseover)** (`Blind@`)
```
#showtooltip Blind
/cast [@mouseover, harm, nodead][harm, nodead] Blind
```

#### Class QoL

**Stealth (no cancel)** (`Stealth`) — Won't drop you out of stealth if pressed again.
```
#showtooltip Stealth
/cast [nostealth] Stealth
```

**Pick Pocket (mouseover)** (`PickPkt@`)
```
#showtooltip Pick Pocket
/cast [@mouseover, harm, nodead][harm, nodead] Pick Pocket
```

**Sap** (`Sap`) — Pick Pocket is its own button (mouseover): a macro that tries Pick Pocket first stops there when it can't be used, so they are not combined.
```
#showtooltip Sap
/cast [harm] Sap
```

**Apply poison (left = main, right = off hand)** (`Poison`) — Change the poison name to the rank you have (e.g. Instant Poison II). The last line confirms the "replace enchant" popup.
```
#showtooltip Instant Poison
/use Instant Poison
/use [button:1] 16; [button:2] 17
/click StaticPopup1Button1
```

**Distract** (`Distract`)
```
#showtooltip Distract
/cast [@cursor] Distract
```

**Grenade at cursor** (`Grenade`) — Swap the item name for the grenade you carry.
```
#showtooltip Iron Grenade
/use [@cursor] Iron Grenade
```

**Sharpening stone (left = main, right = off hand)** (`Stone`) — Swap the item name for the stone you carry. The last line confirms the "replace enchant" popup.
```
#showtooltip Rough Sharpening Stone
/use Rough Sharpening Stone
/use [button:1] 16; [button:2] 17
/click StaticPopup1Button1
```

#### Focus

**Kick focus** (`Kick F`) — Clears your current cast first so the interrupt fires instantly.
```
#showtooltip Kick
/stopcasting
/cast [@focus, harm, exists][harm] Kick
```

**Kidney Shot focus** (`KidneyShot F`)
```
#showtooltip Kidney Shot
/cast [@focus, harm, exists][harm] Kidney Shot
```

**Blind focus** (`Blind F`)
```
#showtooltip Blind
/cast [@focus, harm, exists][harm] Blind
```

### Rogue — Assassination

#### Damage / offensive

**Mutilate** (`Mutilate`)
```
#showtooltip Mutilate
/startattack [harm]
/cast [harm] Mutilate
```

**Cold Blood + Ambush** (`ColdBlood+Amb`) — Requires stealth. While the first spell is on cooldown this button does nothing: use the plain spell button then.
```
#showtooltip Ambush
/cast Cold Blood
/cast [harm] Ambush
```

### Rogue — Subtlety

#### Damage / offensive

**Hemorrhage** (`Hemo`)
```
#showtooltip Hemorrhage
/startattack [harm]
/cast [harm] Hemorrhage
```

## Druid

### Druid — Shared (all specs)

#### Damage / offensive

**Wrath** (`Wrath`) — Level 1. Caster form (leave Bear / Cat Form first).
```
#showtooltip Wrath
/cast [harm] Wrath
```

**Moonfire** (`Moonfire`) — Level 4. Works in caster form (and Moonkin).
```
#showtooltip Moonfire
/cast [harm] Moonfire
```

**Faerie Fire** (`FaerieFire`) — Level 18. Caster form.
```
#showtooltip Faerie Fire
/cast [harm] Faerie Fire
```

**Entangling Roots (mouseover)** (`Roots@`) — Level 8.
```
#showtooltip Entangling Roots
/cast [@mouseover, harm, exists][harm] Entangling Roots
```

**Hibernate (mouseover)** (`Hibernate@`) — Level 18. Beasts and Dragonkin.
```
#showtooltip Hibernate
/cast [@mouseover, harm, exists][harm] Hibernate
```

**Soothe Animal (mouseover)** (`Soothe@`) — Level 22. Takes the enrage off an animal.
```
#showtooltip Soothe Animal
/cast [@mouseover, harm, exists][harm] Soothe Animal
```

#### Mouseover healing / utility

**Heal from any form (Healing Touch, Shift = Regrowth)** (`HealForm`) — Test in beta: Leaves Bear / Cat Form first (every press, even if the heal fails). Without a friendly target it heals you.
```
#showtooltip Healing Touch
/cancelform
/cast [mod:shift, @mouseover, help, nodead][mod:shift, help, nodead][mod:shift, @player] Regrowth; [@mouseover, help, nodead][help, nodead][@player] Healing Touch
```

**Rebirth in combat, Revive outside it** (`Rebirth@`) — Revive is level 12, Rebirth level 20 (needs a seed). Rebirth out of combat uses its long cooldown. Leave Bear / Cat Form first.
```
#showtooltip [combat] Rebirth; Revive
/cast [@mouseover, help, dead, combat][help, dead, combat] Rebirth
/cast [@mouseover, help, dead, nocombat][help, dead, nocombat] Revive
```

**Innervate (mouseover)** (`Innervate@`) — Test in beta: Level 40. Leaves your form first, even when Innervate is on cooldown: keep it off your tanking bar.
```
#showtooltip Innervate
/cancelform
/cast [@mouseover, help, nodead][help, nodead][@player] Innervate
```

#### Cleanse / dispel

**Remove Curse (mouseover)** (`RemCurse@`) — Level 24.
```
#showtooltip Remove Curse
/cast [@mouseover, help, exists][help][@player] Remove Curse
```

**Cure Poison (mouseover)** (`CurePoison@`) — Level 14. Abolish Poison (26) replaces it.
```
#showtooltip Cure Poison
/cast [@mouseover, help, exists][help][@player] Cure Poison
```

**Abolish Poison (mouseover)** (`Abolish@`) — Level 26.
```
#showtooltip Abolish Poison
/cast [@mouseover, help, exists][help][@player] Abolish Poison
```

**Cleanse (Abolish Poison, Shift = Remove Curse)** (`Cleanse`) — One button for both. Poison by default, curse with Shift.
```
#showtooltip Abolish Poison
/cast [mod:shift, @mouseover, help, nodead][mod:shift, help, nodead][mod:shift, @player] Remove Curse; [@mouseover, help, nodead][help, nodead][@player] Abolish Poison
```

#### Buffs

**Mark of the Wild** (`MotW`)
```
#showtooltip Mark of the Wild
/cast [@mouseover, help, exists][help][@player] Mark of the Wild
```

**Thorns** (`Thorns`) — Level 6.
```
#showtooltip Thorns
/cast [@mouseover, help, exists][help][@player] Thorns
```

**Gift of the Wild** (`GotW`) — Level 50. Needs a reagent.
```
#showtooltip Gift of the Wild
/cast [@mouseover, help, exists][help][@player] Gift of the Wild
```

#### Panic / defensive

**Barkskin (Shift = Nature's Grasp)** (`Bark/Grasp`) — Test in beta: Barkskin is level 44, Nature's Grasp level 10. Another Forever guide says neither one drops your form.
```
#showtooltip [mod:shift] Nature's Grasp; Barkskin
/cast [mod:shift] Nature's Grasp; Barkskin
```

#### Class QoL

**Cat Form (Shift = Bear Form)** (`CatBear`) — Dismounts, then shifts. Pressing it again in that form leaves the form. From level 40 write Dire Bear Form.
```
#showtooltip [mod:shift] Bear Form; Cat Form
/dismount
/cast [mod:shift] Bear Form; Cat Form
```

**Travel / Aquatic / Cat Form** (`Travel`) — Aquatic Form level 16, Cat Form 20, Travel Form 30. Until you have Travel Form, delete that part.
```
#showtooltip
/dismount
/cast [swimming] Aquatic Form; [outdoors] Travel Form; Cat Form
```

**Leave form and dismount** (`NoForm`) — Stops a cast, drops any form and gets off your mount.
```
/stopcasting
/cancelform
/dismount
```

**Teleport: Moonglade** (`Moonglade`) — Level 10.
```
#showtooltip Teleport: Moonglade
/cast Teleport: Moonglade
```

#### Focus

**Entangling Roots focus** (`Roots F`)
```
#showtooltip Entangling Roots
/cast [@focus, harm, exists][harm] Entangling Roots
```

**Hibernate focus** (`Hibernate F`)
```
#showtooltip Hibernate
/cast [@focus, harm, exists][harm] Hibernate
```

### Druid — Balance

#### Damage / offensive

**Starfire** (`Starfire`) — Level 20.
```
#showtooltip Starfire
/cast [harm] Starfire
```

**Insect Swarm** (`InsectSwarm`) — Level 30.
```
#showtooltip Insect Swarm
/cast [harm] Insect Swarm
```

**Hurricane at cursor** (`Hurricane`) — Level 40. Channelled: keep still.
```
#showtooltip Hurricane
/cast [@cursor] Hurricane
```

**Starfire (back into Moonkin, Ctrl = Wrath)** (`StarMoon`) — Test in beta: Needs the Moonkin Form talent. In caster form it shifts you into Moonkin Form first; then Starfire, or Wrath while Ctrl is held. Leave out the first part if you don't have the talent.
```
#showtooltip Starfire
/cast [noform] Moonkin Form; [mod:ctrl] Wrath; Starfire
```

**Starsurge** (`Starsurge`) — Test in beta: Forever's own Starsurge (3 sec cast, long range, Arcane damage), not a rune: learn it from your class trainer or talents.
```
#showtooltip Starsurge
/cast [harm] Starsurge
```

**Sunfire** (`Sunfire`) — Test in beta: Forever's own Sunfire (1.5 sec cast, Fire damage), not a rune: learn it from your class trainer or talents.
```
#showtooltip Sunfire
/cast [harm] Sunfire
```

**Starfall** (`Starfall`) — Test in beta: Forever's own Starfall (2 sec cast), not a rune: check that your class trainer or talents give it to you.
```
#showtooltip Starfall
/cast Starfall
```

### Druid — Feral

#### Damage / offensive

**Maul** (`Maul`) — Test in beta: Level 10. Shifts into Bear Form first, then queues Maul on your next hit. The 1 is Bear Form's place on the form bar. From level 40 write Dire Bear Form in every Bear macro.
```
#showtooltip Maul
/startattack [harm]
/cast [noform:1] Bear Form; [harm] Maul
```

**Swipe** (`Swipe`) — Test in beta: Bear AoE. Shifts into Bear Form first.
```
#showtooltip Swipe
/cast [noform:1] Bear Form; Swipe
```

**Lacerate** (`Lacerate`) — Test in beta: Bear bleed that stacks. A trainer spell in Forever, not a rune (Rank 2 is level 50).
```
#showtooltip Lacerate
/startattack [harm]
/cast [noform:1] Bear Form; [harm] Lacerate
```

**Demoralizing Roar** (`DemoRoar`) — Test in beta: Level 10. Shifts into Bear Form first.
```
#showtooltip Demoralizing Roar
/cast [noform:1] Bear Form; Demoralizing Roar
```

**Bash** (`Bash`) — Test in beta: Level 14. Stun, and interrupts a cast. Shifts into Bear Form first.
```
#showtooltip Bash
/startattack [harm]
/cast [noform:1] Bear Form; [harm] Bash
```

**Claw** (`Claw`) — Test in beta: Level 20. Shifts into Cat Form first. 3 = Cat Form's place on the form bar (Bear, Aquatic, Cat): if you haven't learned Aquatic Form (16), change 3 to 2.
```
#showtooltip Claw
/startattack [harm]
/cast [noform:3] Cat Form; [harm] Claw
```

**Shred** (`Shred`) — Test in beta: Level 22. Behind the target. Shifts into Cat Form first (3, or 2 without Aquatic Form).
```
#showtooltip Shred
/startattack [harm]
/cast [noform:3] Cat Form; [harm] Shred
```

**Rake** (`Rake`) — Test in beta: Level 24. Shifts into Cat Form first (3, or 2 without Aquatic Form).
```
#showtooltip Rake
/startattack [harm]
/cast [noform:3] Cat Form; [harm] Rake
```

**Rip** (`Rip`) — Test in beta: Level 20, combo points. Shifts into Cat Form first (3, or 2 without Aquatic Form).
```
#showtooltip Rip
/startattack [harm]
/cast [noform:3] Cat Form; [harm] Rip
```

**Ferocious Bite** (`FeroBite`) — Test in beta: Level 32, combo points. Shifts into Cat Form first (3, or 2 without Aquatic Form).
```
#showtooltip Ferocious Bite
/startattack [harm]
/cast [noform:3] Cat Form; [harm] Ferocious Bite
```

**Ravage (from stealth)** (`Ravage`) — Test in beta: Level 32. Needs Prowl, behind the target.
```
#showtooltip Ravage
/startattack [harm]
/cast [noform:3] Cat Form; [harm] Ravage
```

**Pounce (from stealth)** (`Pounce`) — Test in beta: Level 36. Needs Prowl, stuns.
```
#showtooltip Pounce
/startattack [harm]
/cast [noform:3] Cat Form; [harm] Pounce
```

**Tiger's Fury** (`TigersFury`) — Test in beta: Shifts into Cat Form first (3, or 2 without Aquatic Form).
```
#showtooltip Tiger's Fury
/cast [noform:3] Cat Form; Tiger's Fury
```

**Dash** (`Dash`) — Test in beta: Level 26. Shifts into Cat Form first (3, or 2 without Aquatic Form).
```
#showtooltip Dash
/cast [noform:3] Cat Form; Dash
```

#### Panic / defensive

**Frenzied Regeneration** (`FrenzyRegen`) — Test in beta: Level 36. Turns rage into health.
```
#showtooltip Frenzied Regeneration
/cast [noform:1] Bear Form; Frenzied Regeneration
```

**Enrage** (`Enrage`) — Test in beta: Level 12. Gives rage; lowers your armor while it lasts.
```
#showtooltip Enrage
/cast [noform:1] Bear Form; Enrage
```

#### Targeting helpers

**Growl (mouseover)** (`Growl@`) — Test in beta: Level 10. Taunts what is under your mouse, else your target. Shifts into Bear Form first.
```
#showtooltip Growl
/cast [noform:1] Bear Form; [@mouseover, harm, nodead][harm, nodead] Growl
```

**Challenging Roar** (`ChallRoar`) — Test in beta: Level 28. Taunts everything around you; long cooldown.
```
#showtooltip Challenging Roar
/cast [noform:1] Bear Form; Challenging Roar
```

#### Class QoL

**Bear Form (no accidental unshift)** (`BearForm`) — Test in beta: Does nothing if you are already a bear. From level 40 write Dire Bear Form.
```
#showtooltip Bear Form
/cast [noform:1] Bear Form
```

**Cat Form + Prowl** (`CatProwl`) — Test in beta: Press once for Cat Form, again for Prowl. Pressing it while stealthed doesn't break stealth. 3 = Cat Form's place on the form bar (Bear, Aquatic, Cat): without Aquatic Form change 3 to 2.
```
#showtooltip Prowl
/cast [noform:3] Cat Form; [nostealth] Prowl
```

#### Focus

**Bash focus** (`Bash F`) — Test in beta: Shifts into Bear Form first.
```
#showtooltip Bash
/cast [noform:1] Bear Form; [@focus, harm, exists][harm] Bash
```

### Druid — Restoration

#### Mouseover healing / utility

**Healing Touch** (`HTouch`)
```
#showtooltip Healing Touch
/cast [@mouseover, help, exists][help][@player] Healing Touch
```

**Regrowth** (`Regrowth`) — Level 12.
```
#showtooltip Regrowth
/cast [@mouseover, help, exists][help][@player] Regrowth
```

**Rejuvenation** (`Rejuv`) — Level 4.
```
#showtooltip Rejuvenation
/cast [@mouseover, help, exists][help][@player] Rejuvenation
```

**Wild Growth** (`WildGrowth`) — Level 50. Heals the target and their party.
```
#showtooltip Wild Growth
/cast [@mouseover, help, exists][help][@player] Wild Growth
```

**Tranquility** (`Tranquility`) — Level 30. Channelled: keep still.
```
#showtooltip Tranquility
/cast Tranquility
```

## Shaman

### Shaman — Shared (all specs)

#### Damage / offensive

**Earth Shock (interrupt)** (`EShock`) — Clears your current cast first so the interrupt fires instantly.
```
#showtooltip Earth Shock
/stopcasting
/cast [harm] Earth Shock
```

#### Mouseover healing / utility

**Healing Wave** (`HWave`)
```
#showtooltip Healing Wave
/cast [@mouseover, help, exists][help][@player] Healing Wave
```

**Lesser Healing Wave** (`LHWave`)
```
#showtooltip Lesser Healing Wave
/cast [@mouseover, help, exists][help][@player] Lesser Healing Wave
```

**Chain Heal** (`ChainHeal`)
```
#showtooltip Chain Heal
/cast [@mouseover, help, exists][help][@player] Chain Heal
```

**Ancestral Spirit** (`AncSpirit`)
```
#showtooltip Ancestral Spirit
/cast [@mouseover, help, exists][help][@player] Ancestral Spirit
```

**Riptide** (`Riptide`) — New in Forever. Instant heal + HoT that boosts your next Chain Heal.
```
#showtooltip Riptide
/cast [@mouseover, help, exists][help][@player] Riptide
```

#### Cleanse / dispel

**Cure Poison** (`CurePoison`)
```
#showtooltip Cure Poison
/cast [@mouseover, help, exists][help][@player] Cure Poison
```

**Cure Disease** (`CureDisease`)
```
#showtooltip Cure Disease
/cast [@mouseover, help, exists][help][@player] Cure Disease
```

#### Buffs

**Water Walking** (`WaterWalk`)
```
#showtooltip Water Walking
/cast [@mouseover, help, exists][help][@player] Water Walking
```

**Water Breathing** (`WaterBreath`)
```
#showtooltip Water Breathing
/cast [@mouseover, help, exists][help][@player] Water Breathing
```

#### Panic / defensive

**Self Lesser Healing Wave** (`SelfLHWave`)
```
#showtooltip Lesser Healing Wave
/cast [@player] Lesser Healing Wave
```

**Ghost Wolf (no cancel)** (`GhostWolf`)
```
#showtooltip Ghost Wolf
/cast [noform] Ghost Wolf
```

#### Class QoL

**Totems: melee group (press 4x)** (`MeleeTotems`)
```
#showtooltip Strength of Earth Totem
/castsequence reset=combat Strength of Earth Totem, Windfury Totem, Searing Totem, Mana Spring Totem
```

**Totems: caster group (press 4x)** (`CasterTotems`) — Swap Grace of Air for Tranquil Air if you prefer.
```
#showtooltip Stoneskin Totem
/castsequence reset=combat Stoneskin Totem, Grace of Air Totem, Searing Totem, Mana Spring Totem
```

#### Focus

**Earth Shock interrupt on focus** (`EShock F`) — Clears your current cast first so the interrupt fires instantly.
```
#showtooltip Earth Shock
/stopcasting
/cast [@focus, harm, exists][harm] Earth Shock
```

**Purge focus** (`Purge F`)
```
#showtooltip Purge
/cast [@focus, harm, exists][harm] Purge
```

### Shaman — Elemental

#### Damage / offensive

**Flame Shock > Lava Burst** (`Flame>Lava`) — Opener: Flame Shock, then the boosted Lava Burst.
```
#showtooltip Flame Shock
/castsequence [harm] reset=target/12 Flame Shock, Lava Burst
```

**Elemental Mastery + Chain Lightning** (`EleMastery+CL`) — Test in beta: Elemental Mastery was not seen in the Forever beta talent tree. While the first spell is on cooldown this button does nothing: use the plain spell button then.
```
#showtooltip Chain Lightning
/cast Elemental Mastery
/cast [harm] Chain Lightning
```

**Elemental Mastery + Lightning Bolt** (`EleMastery+LB`) — Test in beta: Elemental Mastery was not seen in the Forever beta talent tree. While the first spell is on cooldown this button does nothing: use the plain spell button then.
```
#showtooltip Lightning Bolt
/cast Elemental Mastery
/cast [harm] Lightning Bolt
```

### Shaman — Enhancement

#### Damage / offensive

**Stormstrike** (`Stormstrike`) — Starts auto-attack too. In Forever it boosts only your NEXT Lightning Bolt, Chain Lightning or Earth Shock, so follow up with one.
```
#showtooltip Stormstrike
/startattack [harm]
/cast [harm] Stormstrike
```

#### Buffs

**Windfury Weapon + Lightning Shield refresh** (`WF+LSRefresh`) — Press twice to reapply both buffs; resets after 2 sec so it doesn't get stuck mid-sequence.
```
#showtooltip Lightning Shield
/castsequence reset=2 Lightning Shield, Windfury Weapon
```

## Hunter

### Hunter — Shared (all specs)

#### Damage / offensive

**Hunter's Mark + send pet (opener)** (`HMark+Pet`) — One press marks the target and sends the pet in.
```
#showtooltip Hunter's Mark
/petattack [harm]
/cast [harm] Hunter's Mark
```

**Volley at cursor** (`Volley`) — Forever removed Volley's cooldown, so it's a real AoE button now. Drops at your mouse cursor, no targeting circle.
```
#showtooltip Volley
/cast [@cursor] Volley
```

**Raptor Strike** (`Raptor`) — Queues on your next swing and turns on auto-attack.
```
#showtooltip Raptor Strike
/startattack [harm]
/cast [harm] Raptor Strike
```

**Wing Clip** (`WingClip`) — Wing Clip alone, for when you only want the slow.
```
#showtooltip Wing Clip
/cast [harm] Wing Clip
```

**Raptor Strike + Wing Clip** (`Raptor+Clip`) — Raptor Strike (on your next swing, no global cooldown) and Wing Clip on one button. Split in 0.56.1 because a macro can stop at the first spell it can't cast, put back at the owner's request. If Wing Clip never goes off while Raptor Strike is on cooldown, use the two single buttons.
```
#showtooltip Raptor Strike
/startattack [harm]
/cast [harm] Raptor Strike
/cast [harm] Wing Clip
```

**Serpent Sting** (`Serpent`) — Serpent Sting on your target.
```
#showtooltip Serpent Sting
/cast [harm] Serpent Sting
```

#### Wand / auto-attack

**Auto Shot (spam-safe)** (`AutoShot`) — Hunter exception: ! stops Auto Shot toggling off. Unlike wand Shoot, it works here.
```
#showtooltip 18
/cast [@targettarget, harm, exists][harm] !Auto Shot
```

#### Buffs

**Aspect: Hawk in combat, Cheetah out** (`AspectHawk`)
```
#showtooltip Aspect of the Hawk
/cast [combat] Aspect of the Hawk; Aspect of the Cheetah
```

**Aspect of the Monkey** (`AspMonkey`) — Always Monkey (no Hawk / Cheetah swap).
```
#showtooltip Aspect of the Monkey
/cast Aspect of the Monkey
```

**Aspect of the Hawk** (`AspHawk`) — Always Hawk, also out of combat.
```
#showtooltip Aspect of the Hawk
/cast Aspect of the Hawk
```

#### Panic / defensive

**Feign Death (clean)** (`FeignDeath`) — Calls the pet back and stops attacking first, so the pet doesn't keep mobs on you.
```
#showtooltip Feign Death
/petfollow
/stopattack
/cast Feign Death
```

#### Class QoL

**Pet attack mouseover / TT** (`PetAtkMOTT`) — Mouseover first, then your target's target, then your target. No #showtooltip: /petattack is not a spell, so it would show a red ?. Pick the icon yourself in the macro window: the claw icon from the pet bar's Attack button (Ability_GhoulFrenzy).
```
/petattack [@mouseover, harm, exists][@targettarget, harm, exists][harm]
```

**Pet attack / Shift = follow** (`PetAtkShift`) — Press to send the pet (mouseover first); Shift+press calls it back. No #showtooltip: /petattack is not a spell, so it would show a red ?. Pick the icon yourself in the macro window: the claw icon from the pet bar's Attack button (Ability_GhoulFrenzy).
```
/petfollow [mod:shift]
/petattack [nomod:shift, @mouseover, harm, exists][nomod:shift, harm]
```

**Pet follow (come back)** (`PetFollow`) — Calls the pet back to you. No #showtooltip: /petattack is not a spell, so it would show a red ?. Pick the icon yourself in the macro window: the claw icon from the pet bar's Attack button (Ability_GhoulFrenzy).
```
/petfollow
```

**Call / Revive / Mend (one button)** (`PetMend`)
```
#showtooltip Mend Pet
/cast [nopet] Call Pet; [@pet, dead] Revive Pet; Mend Pet
```

**Feed Pet** (`FeedPet`) — Swap food item for your pet's diet.
```
#showtooltip Feed Pet
/cast Feed Pet
/use Tough Jerky
```

#### Focus

**Hunter's Mark focus** (`HMark F`)
```
#showtooltip Hunter's Mark
/cast [@focus, harm, exists][harm] Hunter's Mark
```

**Concussive Shot focus** (`ConcShot F`)
```
#showtooltip Concussive Shot
/cast [@focus, harm, exists][harm] Concussive Shot
```

### Hunter — Beast Mastery

#### Damage / offensive

**Bestial Wrath + Rapid Fire burst** (`BW+RapidFire`) — While the first spell is on cooldown this button does nothing: use the plain spell button then.
```
#showtooltip Bestial Wrath
/cast Bestial Wrath
/cast Rapid Fire
```

**Intimidation + pet attack** (`Intim+Pet`) — Intimidation only fires on the pet's next hit, so this sends the pet in too.
```
#showtooltip Intimidation
/petattack [harm]
/cast Intimidation
```

### Hunter — Marksmanship

#### Focus

**Scatter Shot focus** (`ScatterShot F`)
```
#showtooltip Scatter Shot
/cast [@focus, harm, exists][harm] Scatter Shot
```

### Hunter — Survival

#### Damage / offensive

**Raptor Strike** (`SurvRaptor`) — Test in beta: Queues on your next swing and turns on auto-attack.
```
#showtooltip Raptor Strike
/startattack [harm]
/cast [harm] Raptor Strike
```

**Mongoose Bite** (`Mongoose`) — Test in beta: Only usable after you dodge; its own button, since a macro stops at the first spell it can't cast.
```
#showtooltip Mongoose Bite
/cast [harm] Mongoose Bite
```

**Strider Kick** (`StriderKick`) — Test in beta: Survival talent (level 30); its own button for the same reason.
```
#showtooltip Strider Kick
/cast [harm] Strider Kick
```

## Paladin

### Paladin — General (all specs)

#### Damage / offensive

**Holy Strike + auto-attack** (`HStrike`) — New baseline strike in Forever (level 6, 12 sec cooldown).
```
#showtooltip Holy Strike
/startattack [harm]
/cast [harm] Holy Strike
```

**Judgement + Holy Strike** (`Judge+HS`) — Test in beta: Judgement first, Holy Strike after, one button. Works if Judgement doesn't use the global cooldown (a macro stops after the first spell that does); if Holy Strike never fires after Judgement, tell me.
```
#showtooltip Judgement
/startattack [harm]
/cast [harm] Judgement
/cast [harm] Holy Strike
```

**Hammer of Justice** (`HoJ`) — Stuns whatever's under your mouse without changing your target; falls back to your target if nothing's under the mouse.
```
#showtooltip Hammer of Justice
/cast [@mouseover, harm, exists][harm] Hammer of Justice
```

#### Mouseover healing / utility

**Holy Light** (`HL`)
```
#showtooltip Holy Light
/cast [@mouseover, help, exists][help][@player] Holy Light
```

**Flash of Light** (`FoL`)
```
#showtooltip Flash of Light
/cast [@mouseover, help, exists][help][@player] Flash of Light
```

**Lay on Hands** (`LoH`)
```
#showtooltip Lay on Hands
/cast [@mouseover, help, exists][help][@player] Lay on Hands
```

**Blessing of Protection** (`BoP`)
```
#showtooltip Blessing of Protection
/cast [@mouseover, help, exists][help][@player] Blessing of Protection
```

**Blessing of Freedom** (`BoF`)
```
#showtooltip Blessing of Freedom
/cast [@mouseover, help, exists][help][@player] Blessing of Freedom
```

**Redemption** (`Rez`)
```
#showtooltip Redemption
/cast [@mouseover, help, exists][help][@player] Redemption
```

#### Cleanse / dispel

**Cleanse** (`Cleanse`)
```
#showtooltip Cleanse
/cast [@mouseover, help, exists][help][@player] Cleanse
```

**Purify** (`Purify`)
```
#showtooltip Purify
/cast [@mouseover, help, exists][help][@player] Purify
```

#### Buffs

**Blessing of Might** (`BoM`)
```
#showtooltip Blessing of Might
/cast [@mouseover, help, exists][help][@player] Blessing of Might
```

**Blessing of Wisdom** (`BoW`)
```
#showtooltip Blessing of Wisdom
/cast [@mouseover, help, exists][help][@player] Blessing of Wisdom
```

**Blessing of Salvation** (`Salv`)
```
#showtooltip Blessing of Salvation
/cast [@mouseover, help, exists][help][@player] Blessing of Salvation
```

**Blessing of Light** (`BoL`)
```
#showtooltip Blessing of Light
/cast [@mouseover, help, exists][help][@player] Blessing of Light
```

**Greater Blessing of Might** (`GBoM`)
```
#showtooltip Greater Blessing of Might
/cast [@mouseover, help, exists][help][@player] Greater Blessing of Might
```

**Greater Blessing of Wisdom** (`GBoW`)
```
#showtooltip Greater Blessing of Wisdom
/cast [@mouseover, help, exists][help][@player] Greater Blessing of Wisdom
```

**Blessing of Kings** (`BoK`) — Class spell at level 20 in Forever (was a Protection talent).
```
#showtooltip Blessing of Kings
/cast [@mouseover, help, exists][help][@player] Blessing of Kings
```

#### Panic / defensive

**Divine Shield (press again to cancel)** (`Bubble`) — First press bubbles, second press cancels it early.
```
#showtooltip Divine Shield
/cancelaura Divine Shield
/cast Divine Shield
```

**Lay on Hands self** (`LoH me`)
```
#showtooltip Lay on Hands
/cast [@player] Lay on Hands
```

**Blessing of Protection self (press again to cancel)** (`BoP me`) — BoP stops you from attacking, so the second press removes it.
```
#showtooltip Blessing of Protection
/cancelaura Blessing of Protection
/cast [@player] Blessing of Protection
```

#### Class QoL

**Divine Intervention** (`DI`)
```
#showtooltip Divine Intervention
/cast [@mouseover, help, exists][help][@player] Divine Intervention
```

**Auras on one button** (`Auras`) — Plain click: Devotion. Shift: Concentration. Ctrl: Retribution.
```
#showtooltip [mod:shift] Concentration Aura; [mod:ctrl] Retribution Aura; Devotion Aura
/cast [mod:shift] Concentration Aura; [mod:ctrl] Retribution Aura; Devotion Aura
```

#### Focus

**Hammer of Justice focus** (`HoJ F`)
```
#showtooltip Hammer of Justice
/cast [@focus, harm, exists][harm] Hammer of Justice
```

**Turn Undead focus** (`TU F`)
```
#showtooltip Turn Undead
/cast [@focus, harm, exists][harm] Turn Undead
```

### Paladin — Tank

#### Damage / offensive

**Judgement taunt (mouseover)** (`Judge@`) — With Seal of Fury active, Judgement taunts (10 yd). Hover a loose mob to pull it off the healer without changing target.
```
#showtooltip Judgement
/cast [@mouseover, harm, nodead][harm] Judgement
```

#### Buffs

**Blessing of Sanctuary** (`Sanc`)
```
#showtooltip Blessing of Sanctuary
/cast [@mouseover, help, exists][help][@player] Blessing of Sanctuary
```

#### Focus

**Judgement taunt on focus** (`Judge F`) — With Seal of Fury: taunt your focus (e.g. the add you're watching).
```
#showtooltip Judgement
/cast [@focus, harm, exists][harm] Judgement
```

### Paladin — DPS

#### Class QoL

**Seal swap: Command <> Righteousness** (`Twist`) — Test in beta: with the Twist of Light talent, switching seals lets your next swing also apply the old seal. Swap between swings.
```
#showtooltip
/castsequence Seal of Command, Seal of Righteousness
```

#### Focus

**Repentance focus** (`Repent F`)
```
#showtooltip Repentance
/cast [@focus, harm, exists][harm] Repentance
```

### Paladin — Healer

#### Mouseover healing / utility

**Holy Shock (friend or foe)** (`HShock`) — Heals a friendly mouseover/target, damages an enemy one.
```
#showtooltip Holy Shock
/cast [@mouseover, exists][exists][@player] Holy Shock
```

## Warrior

### Warrior — General (all specs)

#### Damage / offensive

**Victory Rush** (`VR`) — New in Forever (level 20). Free, any stance, heals 10% of your max health. Only after a kill that gives XP (20 sec). Its own button: Forever macros can't fall through to another spell.
```
#showtooltip Victory Rush
/startattack [harm]
/cast [harm] Victory Rush
```

**Heroic Strike / Cleave (Shift)** (`HS/Cleave`) — Click: Heroic Strike. Shift-click: Cleave (level 20).
```
#showtooltip [mod:shift] Cleave; Heroic Strike
/startattack [harm]
/cast [mod:shift, harm] Cleave; [harm] Heroic Strike
```

**Hamstring** (`Ham`)
```
#showtooltip Hamstring
/startattack [harm]
/cast [harm] Hamstring
```

**Slam** (`Slam`) — Level 20 in Forever.
```
#showtooltip Slam
/startattack [harm]
/cast [harm] Slam
```

**Execute** (`Exe`) — Level 24. Target under 20% health; Battle or Berserker Stance.
```
#showtooltip Execute
/startattack [harm]
/cast [harm] Execute
```

**Overpower (to Battle)** (`OP`)
```
#showtooltip Overpower
/startattack [harm]
/cast [nostance:1] Battle Stance; [@targettarget, harm, exists][harm] Overpower
```

**Interrupt (Pummel / Shield Bash)** (`Kick`) — Pummel in Berserker Stance (level 38), Shield Bash in Battle or Defensive (needs a shield). No stance swap: use the stance dance.
```
#showtooltip
/startattack [harm]
/cast [stance:3, harm] Pummel; [harm] Shield Bash
```

#### Wand / auto-attack

**Ranged weapon (Bow/Gun/Crossbow/Thrown)** (`Ranged`) — One button for whatever ranged weapon you have equipped.
```
#showtooltip
/cast [equipped:Thrown] Throw; [equipped:Bows] Shoot Bow; [equipped:Guns] Shoot Gun; [equipped:Crossbows] Shoot Crossbow
```

#### Panic / defensive

**Disarm (to Defensive)** (`Disarm`)
```
#showtooltip Disarm
/cast [nostance:2] Defensive Stance; [@targettarget, harm, exists][harm] Disarm
```

**Stance cooldown (Retaliation/Shield Wall/Recklessness)** (`StanceCD`) — Uses the big cooldown of the stance you're in.
```
#showtooltip [stance:1] Retaliation; [stance:2] Shield Wall; [stance:3] Recklessness
/cast [stance:1] Retaliation; [stance:2] Shield Wall; [stance:3] Recklessness
```

**Retaliation with 2H (from Defensive)** (`Retal2H`) — Test in beta: Press twice. 1st: equips your 2H (shield goes to bags, keep a free slot) and swaps to Battle Stance. 2nd: Retaliation, then back to Defensive. Does the swap back fire in the same press? If not, use your Stance swap button: a 3rd press won't do it, since Forever macros stop at Retaliation once it's on cooldown. Retaliation hits back with your weapon, so the 2H makes it hit much harder vs packs. Fill in your own 2H name; swap back to 1H + shield yourself.
```
#showtooltip Retaliation
/equip Your Two-Hander Name
/cast [nostance:1] Battle Stance
/cast [stance:1] Retaliation
/cast [stance:1] Defensive Stance
```

#### Class QoL

**Charge / Intercept (one button)** (`Charge`) — Out of combat: Charge. In combat: Intercept (level 30). Tactical Mastery (now trained) keeps up to 10 rage on a stance swap. Plain "Charge" uses the highest rank you know (owner test 2026-10-15, so no rank in the name).
```
#showtooltip Charge
/cast [nocombat, nostance:1] Battle Stance; [nocombat, @targettarget, harm, exists][nocombat, harm] Charge; [nostance:3] Berserker Stance; [@targettarget, harm, exists][harm] Intercept
```

**Charge + Rend (opener)** (`Charge+Rend`) — Charges in (out of combat only) then opens with Rend. Plain "Charge" uses the highest rank you know (owner test 2026-10-15, so no rank in the name).
```
#showtooltip Charge
/startattack [harm]
/cast [nocombat, nostance:1] Battle Stance
/cast [nocombat, harm] Charge
/cast [harm] Rend
```

**Taunt (to Defensive)** (`Taunt`) — Target the friend being hit: TT is the mob.
```
#showtooltip Taunt
/cast [nostance:2] Defensive Stance; [@targettarget, harm, exists][harm] Taunt
```

**Mocking Blow (to Battle)** (`Mock`)
```
#showtooltip Mocking Blow
/startattack [harm]
/cast [nostance:1] Battle Stance; [@targettarget, harm, exists][harm] Mocking Blow
```

**Stance swap (Battle <> Defensive)** (`Stances`) — One button swaps Battle <> Defensive (from Berserker or no stance it goes to Battle). Only two stances on purpose: a three-stance cycle gets stuck in Defensive Stance before level 30, because Berserker Stance isn't learned yet.
```
#showtooltip [stance:1] Defensive Stance; Battle Stance
/cast [stance:1] Defensive Stance; Battle Stance
```

**Stance toggle (Battle <> Defensive, mods for others)** (`StanceTog`) — Click swaps Battle <> Defensive. Ctrl = Berserker (level 30). Alt = Defensive.
```
#showtooltip
/cast [mod:ctrl, nostance:3] Berserker Stance; [mod:alt, nostance:2] Defensive Stance; [stance:1] Defensive Stance; Battle Stance
```

**Off-hand <> shield swap** (`OHSwap`) — Fill in your own shield and off-hand item names.
```
/equipslot [noequipped:Shields] 17 Your Shield
/equipslot [equipped:Shields] 17 Your Offhand
```

#### Focus

**Interrupt focus (Pummel / Shield Bash)** (`Kick F`) — Interrupts your focus (or your target if you have no focus): Pummel in Berserker Stance, Shield Bash in Battle or Defensive (needs a shield). No stance swap.
```
#showtooltip
/cast [stance:3, @focus, harm, exists][stance:3, harm] Pummel; [@focus, harm, exists][harm] Shield Bash
```

### Warrior — Tank

#### Damage / offensive

**Sunder Armor** (`Sunder`) — Your spam button. Starts auto-attack.
```
#showtooltip Sunder Armor
/startattack [harm]
/cast [harm] Sunder Armor
```

**Revenge** (`Rev`) — Defensive Stance, after a block, dodge or parry: press it whenever it lights up (best threat per rage). Its own button because Forever macros stop at the first spell you know but can't use right now, so "Revenge, else Sunder" never reaches Sunder (tested 2026-10-09).
```
#showtooltip Revenge
/startattack [harm]
/cast [harm] Revenge
```

**Shield Block + Sunder Armor** (`SBlk+Sund`) — Test in beta: Shield Block is off the global cooldown, so it fires with Sunder in one press. Unknown on Forever: whether Sunder still goes out while Shield Block is on cooldown (if not, use plain Sunder between blocks). Needs a shield and Defensive Stance. While the first spell is on cooldown this button does nothing: use the plain spell button then.
```
#showtooltip Shield Block
/startattack [harm]
/cast Shield Block
/cast [harm] Sunder Armor
```

**Shield Block + Revenge** (`SBlk+Rev`) — Test in beta: Shield Block is off the global cooldown, so it fires with Revenge in one press. Forever stops a macro at the first spell you know but can't use right now, so while Shield Block is on cooldown Revenge will not go out from this button: use the plain Revenge button then. Needs a shield and Defensive Stance.
```
#showtooltip Shield Block
/startattack [harm]
/cast Shield Block
/cast [harm] Revenge
```

**Concussion Blow** (`Concuss`) — Talent (in our level-30 tank build).
```
#showtooltip Concussion Blow
/startattack [harm]
/cast [harm] Concussion Blow
```

**Shield Slam** (`SSlam`) — Talent, level 40. Forever: about double the damage.
```
#showtooltip Shield Slam
/startattack [harm]
/cast [harm] Shield Slam
```

#### Class QoL

**Charge + Rend (Vanguard, any stance)** (`VCharge`) — With the Vanguard talent (level-30 tank build) Charge works in Defensive Stance, so no stance swap. Out of combat it charges, then press again for Rend (it fails while you are still out of range). Plain "Charge" uses the highest rank you know (owner test 2026-10-15, so no rank in the name).
```
#showtooltip Charge
/startattack [harm]
/cast [nocombat, harm] Charge
/cast [harm] Rend
```

**Taunt (mouseover)** (`Taunt@`) — Defensive Stance. Hover a loose mob to taunt it without changing target.
```
#showtooltip Taunt
/cast [@mouseover, harm, nodead][harm] Taunt
```

### Warrior — DPS

#### Damage / offensive

**Sweeping Strikes (to Battle)** (`Sweep`) — Arms talent (in our level-30 Arms build). Pair with Cleave.
```
#showtooltip Sweeping Strikes
/cast [nostance:1] Battle Stance; Sweeping Strikes
```

**Mortal Strike** (`MS`) — Arms talent, level 40.
```
#showtooltip Mortal Strike
/startattack [harm]
/cast [harm] Mortal Strike
```

**Bloodthirst** (`BT`) — Fury talent, level 40.
```
#showtooltip Bloodthirst
/startattack [harm]
/cast [harm] Bloodthirst
```

**Whirlwind (to Berserker)** (`WW`) — Level 36.
```
#showtooltip Whirlwind
/cast [nostance:3] Berserker Stance; Whirlwind
```
