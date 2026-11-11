# Unit / Item API contract ledger - 2026-11-10

Main TacoTip addon only; TacoTip_Extras excluded by operator instruction. Shapes quoted from
Blizzard_APIDocumentationGenerated/UnitDocumentation.lua and ItemDocumentation.lua at the pin.

Call forms covered: `Fn(...)`, `pcall(Fn, ...)`, `_G.Fn`, file-scope aliases, AND ItemLocation method
calls (`item:GetItemLink()`, `item:IsItemDataCached()`), which are the ItemLocationMixin sugar over
`C_Item.GetItemLink(itemLocation)` / `C_Item.IsItemDataCached(itemLocation)` and are resolved to that
contract. A `method` row means the receiver is the ItemLocation.

This records the CONTRACT and the handling it REQUIRES. It does not certify the handling is present.

## `Libs/LibForeverInspector/LibForeverInspector.lua` - 28 call sites

| line | call | arg | kind | boundary | wrapped | documented returns | required handling |
| ---: | :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| 102 | `UnitGUID` | `-` | - | yes | yes | result:WOWGUID:nilable | nil-test,secrecy-test,arg-test |
| 132 | `UnitIsUnit` | `-` | - | yes | yes | result:bool:non-nil | secrecy-test,arg-test |
| 162 | `UnitExists` | `-` | - | yes | yes | result:bool:non-nil | arg-test |
| 173 | `UnitIsPlayer` | `-` | - | yes | yes | result:bool:non-nil | arg-test |
| 184 | `UnitIsConnected` | `-` | - | yes | yes | isConnected:bool:non-nil | arg-test |
| 195 | `UnitIsDeadOrGhost` | `-` | - | yes | yes | result:bool:non-nil | arg-test |
| 1047 | `UnitClass` | `"player"` | - | no | no | className:cstring:non-nil,conditional-secret; classFilename:cstring:non-nil; classID:number:non-nil | pcall-ok,secrecy-test,arg-test |
| 3223 | `UnitIsPlayer` | `arg` | - | yes | no | result:bool:non-nil | arg-test |
| 3473 | `UnitClass` | `-` | - | no | yes | className:cstring:non-nil,conditional-secret; classFilename:cstring:non-nil; classID:number:non-nil | pcall-ok,secrecy-test,arg-test |
| 3492 | `UnitSex` | `-` | - | no | yes | sex:number:nilable | nil-test,secrecy-test,arg-test |
| 4187 | `GetItemInfo` | `link` | - | no | no | itemName:cstring:non-nil; itemLink:cstring:non-nil; itemQuality:ItemQuality:non-nil; itemLevel:number:non-nil; | pcall-ok,nil-test,arg-test |
| 4196 | `IsItemDataCached` | `self` | method | no | no | isCached:bool:non-nil | arg-test |
| 4208 | `IsItemDataCached` | `self` | method | no | no | isCached:bool:non-nil | arg-test |
| 4640 | `UnitExists` | `"target"` | - | no | no | result:bool:non-nil | arg-test |
| 4641 | `UnitIsPlayer` | `"target"` | - | no | no | result:bool:non-nil | arg-test |
| 4647 | `UnitExists` | `"mouseover"` | - | no | no | result:bool:non-nil | arg-test |
| 4648 | `UnitIsPlayer` | `"mouseover"` | - | no | no | result:bool:non-nil | arg-test |
| 4927 | `UnitExists` | `insFrame.unit` | - | no | no | result:bool:non-nil | arg-test |
| 4987 | `UnitDistanceSquared` | `unit` | - | no | no | distance:number:non-nil; checkedDistance:bool:non-nil | arg-test |
| 5014 | `UnitDistanceSquared` | `unit` | - | no | no | distance:number:non-nil; checkedDistance:bool:non-nil | arg-test |
| 5841 | `UnitExists` | `"player"` | - | no | no | result:bool:non-nil | arg-test |
| 5841 | `UnitIsConnected` | `"player"` | - | no | no | isConnected:bool:non-nil | arg-test |
| 5841 | `UnitIsDeadOrGhost` | `"player"` | - | no | no | result:bool:non-nil | arg-test |
| 5885 | `UnitExists` | `"target"` | - | no | no | result:bool:non-nil | arg-test |
| 5900 | `UnitGroupRolesAssigned` | `-` | - | no | yes | result:cstring:non-nil | secrecy-test,arg-test |
| 5916 | `UnitExists` | `-` | - | no | yes | result:bool:non-nil | arg-test |
| 5933 | `UnitExists` | `-` | - | no | yes | result:bool:non-nil | arg-test |
| 5973 | `UnitExists` | `unitHint` | - | no | no | result:bool:non-nil | arg-test |

## `main.lua` - 54 call sites

| line | call | arg | kind | boundary | wrapped | documented returns | required handling |
| ---: | :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| 311 | `UnitGUID` | `-` | - | yes | yes | result:WOWGUID:nilable | nil-test,secrecy-test,arg-test |
| 322 | `UnitExists` | `-` | - | yes | yes | result:bool:non-nil | arg-test |
| 335 | `UnitIsPlayer` | `-` | - | yes | yes | result:bool:non-nil | arg-test |
| 348 | `UnitIsUnit` | `-` | - | yes | yes | result:bool:non-nil | secrecy-test,arg-test |
| 361 | `UnitInParty` | `-` | - | yes | yes | result:bool:non-nil | arg-test |
| 374 | `UnitInRaid` | `-` | - | yes | yes | result:luaIndex:nilable | nil-test,secrecy-test,arg-test |
| 387 | `UnitIsPVP` | `-` | - | yes | yes | result:bool:non-nil | secrecy-test,arg-test |
| 561 | `UnitClass` | `"player"` | - | no | no | className:cstring:non-nil,conditional-secret; classFilename:cstring:non-nil; classID:number:non-nil | pcall-ok,secrecy-test,arg-test |
| 723 | `UnitIsOtherPlayersPet` | `-` | - | no | yes | result:bool:non-nil | arg-test |
| 913 | `UnitClass` | `-` | - | no | yes | className:cstring:non-nil,conditional-secret; classFilename:cstring:non-nil; classID:number:non-nil | pcall-ok,secrecy-test,arg-test |
| 951 | `UnitCanAttack` | `-` | - | no | yes | result:bool:non-nil | arg-test |
| 952 | `UnitIsPlayer` | `-` | - | no | yes | result:bool:non-nil | arg-test |
| 965 | `UnitLevel` | `-` | - | no | yes | result:number:non-nil | arg-test |
| 972 | `UnitLevel` | `-` | - | no | yes | result:number:non-nil | arg-test |
| 993 | `UnitLevel` | `-` | - | no | yes | result:number:non-nil | arg-test |
| 1839 | `SetPortraitTexture` | `-` | - | no | yes | NONE | arg-test |
| 1889 | `UnitPowerMax` | `-` | - | no | yes | maxPower:number:non-nil | secrecy-test,arg-test |
| 2521 | `getItemInfo` | `-` | alias | no | yes | itemName:cstring:non-nil; itemLink:cstring:non-nil; itemQuality:ItemQuality:non-nil; itemLevel:number:non-nil; | pcall-ok,nil-test,arg-test |
| 2531 | `request` | `-` | alias | no | yes | NONE | arg-test |
| 2707 | `UnitName` | `-` | - | no | yes | unitName:cstring:non-nil; unitServer:cstring:non-nil | secrecy-test |
| 2889 | `UnitName` | `unitTarget` | - | no | no | unitName:cstring:non-nil; unitServer:cstring:non-nil | secrecy-test |
| 2919 | `UnitClass` | `-` | - | no | yes | className:cstring:non-nil,conditional-secret; classFilename:cstring:non-nil; classID:number:non-nil | pcall-ok,secrecy-test,arg-test |
| 2995 | `UnitClass` | `-` | - | no | yes | className:cstring:non-nil,conditional-secret; classFilename:cstring:non-nil; classID:number:non-nil | pcall-ok,secrecy-test,arg-test |
| 2996 | `UnitRace` | `-` | - | no | yes | localizedRaceName:cstring:non-nil; englishRaceName:cstring:non-nil; raceID:number:non-nil | pcall-ok,secrecy-test,arg-test |
| 2997 | `UnitLevel` | `-` | - | no | yes | result:number:non-nil | arg-test |
| 3131 | `UnitIsSameServer` | `-` | - | no | yes | result:bool:non-nil | arg-test |
| 3135 | `UnitName` | `-` | - | no | yes | unitName:cstring:non-nil; unitServer:cstring:non-nil | secrecy-test |
| 3146 | `UnitPVPName` | `-` | - | no | yes | result:string:non-nil | secrecy-test,arg-test |
| 3177 | `UnitFactionGroup` | `-` | - | no | yes | factionGroupTag:cstring:non-nil; localized:cstring:non-nil | arg-test |
| 3187 | `UnitClass` | `-` | - | no | yes | className:cstring:non-nil,conditional-secret; classFilename:cstring:non-nil; classID:number:non-nil | pcall-ok,secrecy-test,arg-test |
| 3196 | `UnitGroupRolesAssigned` | `-` | - | no | yes | result:cstring:non-nil | secrecy-test,arg-test |
| 3661 | `UnitPowerType` | `-` | - | no | yes | powerType:PowerType:non-nil; powerTypeToken:string:non-nil; rgbX:number:non-nil; rgbY:number:non-nil; rgbZ:num | pcall-ok,arg-test |
| 3665 | `UnitPowerMax` | `-` | - | no | yes | maxPower:number:non-nil | secrecy-test,arg-test |
| 3666 | `UnitPower` | `-` | - | no | yes | power:number:non-nil | secrecy-test,arg-test |
| 3870 | `C_Item.GetItemLinkByGUID` | `-` | - | no | yes | itemLink:string:nilable | nil-test,arg-test |
| 3910 | `IsEquippableItem` | `-` | - | no | yes | result:bool:non-nil | arg-test |
| 3930 | `getItemInfoFn` | `-` | alias | no | yes | itemName:cstring:non-nil; itemLink:cstring:non-nil; itemQuality:ItemQuality:non-nil; itemLevel:number:non-nil; | pcall-ok,nil-test,arg-test |
| 3950 | `UnitClass` | `-` | - | no | yes | className:cstring:non-nil,conditional-secret; classFilename:cstring:non-nil; classID:number:non-nil | pcall-ok,secrecy-test,arg-test |
| 4019 | `GetItemInfoInstant` | `-` | - | yes | yes | itemID:number:non-nil; itemType:cstring:non-nil; itemSubType:cstring:non-nil; itemEquipLoc:cstring:non-nil; ic | pcall-ok,arg-test |
| 4025 | `RequestLoadItemDataByID` | `-` | - | yes | yes | NONE | arg-test |
| 4030 | `IsItemDataCached` | `-` | - | yes | yes | isCached:bool:non-nil | arg-test |
| 5160 | `fnUnitName` | `activeUnit` | alias | no | no | unitName:cstring:non-nil; unitServer:cstring:non-nil | secrecy-test |
| 5162 | `fnUnitGUID` | `activeUnit` | alias | no | no | result:WOWGUID:nilable | nil-test,secrecy-test,arg-test |
| 5165 | `fnUnitLevel` | `activeUnit` | alias | no | no | result:number:non-nil | arg-test |
| 5167 | `fnUnitClass` | `activeUnit` | alias | no | no | className:cstring:non-nil,conditional-secret; classFilename:cstring:non-nil; classID:number:non-nil | pcall-ok,secrecy-test,arg-test |
| 5169 | `fnUnitRace` | `activeUnit` | alias | no | no | localizedRaceName:cstring:non-nil; englishRaceName:cstring:non-nil; raceID:number:non-nil | pcall-ok,secrecy-test,arg-test |
| 5197 | `UnitIsVisible` | `-` | - | no | yes | result:bool:non-nil | arg-test |
| 5203 | `fnUnitIsConnected` | `-` | alias | no | yes | isConnected:bool:non-nil | arg-test |
| 5209 | `fnUnitCanAttack` | `-` | alias | no | yes | result:bool:non-nil | arg-test |
| 5219 | `UnitDistanceSquared` | `-` | - | no | yes | distance:number:non-nil; checkedDistance:bool:non-nil | arg-test |
| 5282 | `getItemInfo` | `-` | alias | no | yes | itemName:cstring:non-nil; itemLink:cstring:non-nil; itemQuality:ItemQuality:non-nil; itemLevel:number:non-nil; | pcall-ok,nil-test,arg-test |
| 5303 | `fnUnitClass` | `activeUnit` | alias | no | no | className:cstring:non-nil,conditional-secret; classFilename:cstring:non-nil; classID:number:non-nil | pcall-ok,secrecy-test,arg-test |
| 5881 | `UnitName` | `"player"` | - | no | no | unitName:cstring:non-nil; unitServer:cstring:non-nil | secrecy-test |
| 6088 | `GetItemInfo` | `-` | - | no | yes | itemName:cstring:non-nil; itemLink:cstring:non-nil; itemQuality:ItemQuality:non-nil; itemLevel:number:non-nil; | pcall-ok,nil-test,arg-test |

## `options.lua` - 4 call sites

| line | call | arg | kind | boundary | wrapped | documented returns | required handling |
| ---: | :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| 4285 | `SetPortraitTexture` | `-` | - | no | yes | NONE | arg-test |
| 4751 | `SetPortraitTexture` | `-` | - | no | yes | NONE | arg-test |
| 4981 | `UnitGUID` | `"player"` | - | no | no | result:WOWGUID:nilable | nil-test,secrecy-test,arg-test |
| 5065 | `UnitGUID` | `"player"` | - | no | no | result:WOWGUID:nilable | nil-test,secrecy-test,arg-test |

## `gearscore.lua` - 25 call sites

| line | call | arg | kind | boundary | wrapped | documented returns | required handling |
| ---: | :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| 103 | `RequestLoadItemDataByID` | `itemID` | - | no | no | NONE | arg-test |
| 117 | `rawRequestLoadItemDataByID` | `-` | alias | no | yes | NONE | arg-test |
| 119 | `GetItemInfo` | `...` | - | no | no | itemName:cstring:non-nil; itemLink:cstring:non-nil; itemQuality:ItemQuality:non-nil; itemLevel:number:non-nil; | pcall-ok,nil-test,arg-test |
| 123 | `fn` | `...` | alias | no | no | itemName:cstring:non-nil; itemLink:cstring:non-nil; itemQuality:ItemQuality:non-nil; itemLevel:number:non-nil; | pcall-ok,nil-test,arg-test |
| 256 | `UnitIsUnit` | `-` | - | yes | yes | result:bool:non-nil | secrecy-test,arg-test |
| 272 | `UnitIsPlayer` | `arg` | - | yes | no | result:bool:non-nil | arg-test |
| 273 | `UnitGUID` | `-` | - | yes | yes | result:WOWGUID:nilable | nil-test,secrecy-test,arg-test |
| 329 | `RequestLoadItemDataByID` | `-` | - | no | yes | NONE | arg-test |
| 394 | `RequestLoadItemDataByID` | `-` | - | no | yes | NONE | arg-test |
| 414 | `GetItemInfo` | `ItemLink` | - | no | no | itemName:cstring:non-nil; itemLink:cstring:non-nil; itemQuality:ItemQuality:non-nil; itemLevel:number:non-nil; | pcall-ok,nil-test,arg-test |
| 472 | `UnitGUID` | `-` | - | no | yes | result:WOWGUID:nilable | nil-test,secrecy-test,arg-test |
| 517 | `IsItemDataCached` | `mainHandItem` | method | no | no | isCached:bool:non-nil | arg-test |
| 518 | `GetItemLink` | `mainHandItem` | method | no | no | itemLink:string:nilable | nil-test,arg-test |
| 521 | `GetItemID` | `mainHandItem` | method | no | no | itemID:number:non-nil | arg-test |
| 542 | `RequestLoadItemDataByID` | `itemID` | - | no | no | NONE | arg-test |
| 548 | `IsItemDataCached` | `offHandItem` | method | no | no | isCached:bool:non-nil | arg-test |
| 549 | `GetItemLink` | `offHandItem` | method | no | no | itemLink:string:nilable | nil-test,arg-test |
| 552 | `GetItemID` | `offHandItem` | method | no | no | itemID:number:non-nil | arg-test |
| 570 | `RequestLoadItemDataByID` | `itemID` | - | no | no | NONE | arg-test |
| 583 | `GetItemInfo` | `mainHandLink` | - | no | no | itemName:cstring:non-nil; itemLink:cstring:non-nil; itemQuality:ItemQuality:non-nil; itemLevel:number:non-nil; | pcall-ok,nil-test,arg-test |
| 584 | `GetItemInfo` | `offHandLink` | - | no | no | itemName:cstring:non-nil; itemLink:cstring:non-nil; itemQuality:ItemQuality:non-nil; itemLevel:number:non-nil; | pcall-ok,nil-test,arg-test |
| 607 | `IsItemDataCached` | `item` | method | no | no | isCached:bool:non-nil | arg-test |
| 608 | `GetItemLink` | `item` | method | no | no | itemLink:string:nilable | nil-test,arg-test |
| 627 | `GetItemID` | `item` | method | no | no | itemID:number:non-nil | arg-test |
| 646 | `RequestLoadItemDataByID` | `itemID` | - | no | no | NONE | arg-test |

## `pawn.lua` - 8 call sites

| line | call | arg | kind | boundary | wrapped | documented returns | required handling |
| ---: | :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| 120 | `UnitIsUnit` | `-` | - | yes | yes | result:bool:non-nil | secrecy-test,arg-test |
| 138 | `UnitIsPlayer` | `-` | - | yes | yes | result:bool:non-nil | arg-test |
| 140 | `UnitGUID` | `-` | - | yes | yes | result:WOWGUID:nilable | nil-test,secrecy-test,arg-test |
| 211 | `UnitGUID` | `-` | - | no | yes | result:WOWGUID:nilable | nil-test,secrecy-test,arg-test |
| 250 | `IsItemDataCached` | `item` | method | no | no | isCached:bool:non-nil | arg-test |
| 252 | `GetItemLink` | `item` | method | no | no | itemLink:string:nilable | nil-test,arg-test |
| 262 | `GetItemID` | `item` | method | no | no | itemID:number:non-nil | arg-test |
| 282 | `RequestLoadItemDataByID` | `itemID` | - | no | no | NONE | arg-test |

## total: 119 call sites

