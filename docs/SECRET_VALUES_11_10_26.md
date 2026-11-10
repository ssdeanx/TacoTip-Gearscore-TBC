# WoW Forever (Camelot / Interface 16001) Secret Values & Instance Combat Lockdown Reference

**Document Date**: November 10, 2026  
**Target Environment**: WoW Forever (`WOW_PROJECT_ID == 1`, Mainline / Camelot engine, Interface `16001`)  
**Source Checkout**: `/home/sam/wow-ui-source` @ `origin/forever` (Commit: `eac30af59`, Build 1.60.1 70790)  
**Addon Scope**: TacoTip Core (`main.lua`, `gearscore.lua`, `pawn.lua`, `options.lua`)  

---

## 1. Executive Summary & Root Cause Architecture

Inside instances (dungeons, raids, arenas), combat triggers an engine-level restriction subsystem that alters how unit information and tooltips behave.
Unlike older Classic clients (Era 11509, TBC 20506, Titanforge 38002) which only had protected action functions (e.g., `CastSpellByName`), WoW Forever inherits the modern **Mainline (Dragonflight/War Within) Secret Values & Execution Taint Architecture**.

Under this architecture:
1. **Secret Arguments (`AllowedWhenUntainted`)**:
   Almost every unit API in Blizzard generated documentation is annotated with `SecretArguments = "AllowedWhenUntainted"`.
   - If Blizzard native (untainted) UI calls the API with a secret value, the call succeeds.
   - If an **addon (tainted execution)** passes a secret value (such as a secret unit token or restricted GUID), Blizzard's engine immediately halts execution with:
     ```
     bad argument #1 to 'UnitExists' (Usage: local result = UnitExists([unit]). Secret values are only allowed during untainted execution for this argument.)
     ```
2. **Secret Return Values (Secret Booleans, Secret Strings, Secret Numbers)**:
   When combat occurs in an instance, specific engine restrictions activate:
   - `UnitIdentityRestricted = true`: `UnitGUID`, `UnitClass`, `UnitRace`, `UnitInRaid`, `UnitIsPVP`, `UnitGroupRolesAssigned`, `UnitTokenFromGUID` return secret values.
   - `UnitNameIdentityRestricted = true`: `UnitName` returns secret string.
   - `UnitComparisonRestricted = true`: `UnitIsUnit` returns a **secret boolean**.
   - `UnitPowerRestricted = true`: `UnitPower` returns secret number.
   - `UnitPowerMaxRestricted = true`: `UnitPowerMax` returns secret number.
   - `UnitHealthMaxRestricted = true`: `UnitHealthMax` returns secret number.
   - `SecretReturns = true`: `UnitHealth` returns secret number.
3. **The Secret Boolean Trap**:
   In Lua, evaluating truthiness on a secret boolean (`if secretBool then`, `not secretBool`, `secretBool == true`, `secretBool ~= false`, `secretBool == nil`) raises an uncatchable syntax/engine trap:
   ```
   attempt to perform boolean test on a secret boolean value (execution tainted by 'TacoTip')
   ```
4. **The `issecretvalue` / `canaccessvalue` Trap**:
   Even `issecretvalue` and `canaccessvalue` themselves declare `SecretArguments = "AllowedWhenUntainted"`!
   When called from tainted execution on a secret value, `issecretvalue(v)` throws `bad argument #1 ... Secret values are only allowed during untainted execution`.
   - Therefore, a naive `if issecretvalue(v) then` or checking `ok and isSec` fails because `ok` is `false` when `v` is secret!
   - **The Correct Rule**: `not okSecret or isSec == true`. If `pcall(issecretvalue, v)` throws an error during tainted execution, `v` **is definitively a secret value**.

---

## 2. Complete API Catalog & Data Shapes (`origin/forever`)

### Core Detection & Safety Utilities

#### `issecretvalue`
- **Documentation File**: `Interface/AddOns/Blizzard_APIDocumentationGenerated/FrameScriptDocumentation.lua`
- **Secret Arguments**: `AllowedWhenUntainted` (Throws if tainted execution passes a secret value!)

```lua
{
			Name = "issecretvalue",
			Type = "Function",
			SecureHooksAllowed = false,
			SecretArguments = "AllowedWhenUntainted",
			Documentation = { "Returns true if a supplied value is a secret value." },

			Arguments =
			{
				{ Name = "value", Type = "LuaValueReference", Nilable = false },
			},

			Returns =
			{
				{ Name = "isSecret", Type = "bool", Nilable = false },
			},
		},
```

**Combat Lockdown Behavior & TacoTip Rule**:
- *Risk*: Declares `SecretArguments = "AllowedWhenUntainted"`. Throws when called on a secret value from tainted addon execution.
- *Defense*: Wrap in `pcall`. If `not okSecret`, the value is secret.

#### `canaccessvalue`
- **Documentation File**: `Interface/AddOns/Blizzard_APIDocumentationGenerated/FrameScriptDocumentation.lua`
- **Secret Arguments**: `AllowedWhenUntainted` (Throws if tainted execution passes a secret value!)

```lua
{
			Name = "canaccessvalue",
			Type = "Function",
			SecureHooksAllowed = false,
			SecretArguments = "AllowedWhenUntainted",
			Documentation = { "Returns true if the immediate calling function has appropriate permissions to access and operate on a specific value." },

			Arguments =
			{
				{ Name = "value", Type = "LuaValueReference", Nilable = false },
			},

			Returns =
			{
				{ Name = "canAccessValue", Type = "bool", Nilable = false },
			},
		},
```

**Combat Lockdown Behavior & TacoTip Rule**:
- *Risk*: Declares `SecretArguments = "AllowedWhenUntainted"`. Throws when called on a secret value from tainted addon execution.
- *Defense*: Wrap in `pcall`. If `not okSecret`, the value is secret.

### Unit Existence & Token Resolution

#### `UnitExists`
- **Documentation File**: `Interface/AddOns/Blizzard_APIDocumentationGenerated/UnitDocumentation.lua`
- **Secret Arguments**: `AllowedWhenUntainted` (Throws if tainted execution passes a secret value!)

```lua
{
			Name = "UnitExists",
			Type = "Function",
			SecretArguments = "AllowedWhenUntainted",

			Arguments =
			{
				{ Name = "unit", Type = "UnitToken", Nilable = true },
			},

			Returns =
			{
				{ Name = "result", Type = "bool", Nilable = false },
			},
		},
```

**Combat Lockdown Behavior & TacoTip Rule**:
- *Risk*: If `unit` token was obtained from a restricted source (e.g. `TooltipUtil.GetDisplayedUnit` -> `UnitTokenFromGUID`), passing it to bare `UnitExists` throws `bad argument #1`.
- *Defense*: Must use `safeUnitExists(unit)` / `safeUnitIsPlayer(unit)` with `isSecretValue` check and `pcall` wrapper.

#### `UnitIsPlayer`
- **Documentation File**: `Interface/AddOns/Blizzard_APIDocumentationGenerated/UnitDocumentation.lua`
- **Secret Arguments**: `AllowedWhenUntainted` (Throws if tainted execution passes a secret value!)

```lua
{
			Name = "UnitIsPlayer",
			Type = "Function",
			SecretArguments = "AllowedWhenUntainted",

			Arguments =
			{
				{ Name = "unit", Type = "UnitToken", Nilable = true },
				{ Name = "partyIndex", Type = "luaIndex", Nilable = true },
			},

			Returns =
			{
				{ Name = "result", Type = "bool", Nilable = false },
			},
		},
```

**Combat Lockdown Behavior & TacoTip Rule**:
- *Risk*: If `unit` token was obtained from a restricted source (e.g. `TooltipUtil.GetDisplayedUnit` -> `UnitTokenFromGUID`), passing it to bare `UnitExists` throws `bad argument #1`.
- *Defense*: Must use `safeUnitExists(unit)` / `safeUnitIsPlayer(unit)` with `isSecretValue` check and `pcall` wrapper.

#### `UnitIsUnit`
- **Documentation File**: `Interface/AddOns/Blizzard_APIDocumentationGenerated/UnitDocumentation.lua`
- **Secret Arguments**: `AllowedWhenUntainted` (Throws if tainted execution passes a secret value!)
- **Restriction Trigger**: `SecretWhenUnitComparisonRestricted = true,`

```lua
{
			Name = "UnitIsUnit",
			Type = "Function",
			RequiresComparableUnitTokens = true,
			SecretWhenUnitComparisonRestricted = true,
			SecretArguments = "AllowedWhenUntainted",

			Arguments =
			{
				{ Name = "unit1", Type = "UnitToken", Nilable = false },
				{ Name = "unit2", Type = "UnitToken", Nilable = false },
			},

			Returns =
			{
				{ Name = "result", Type = "bool", Nilable = false },
			},
		},
```

**Combat Lockdown Behavior & TacoTip Rule**:
- *Risk*: In combat in instances, `SecretWhenUnitComparisonRestricted = true`. The return value is a **secret boolean**. Testing `isU == true` or `if isU` throws `attempt to perform boolean test on a secret boolean value`.
- *Defense*: Must use `safeUnitIsUnit(u1, u2)` which inspects `isSecretValue` on both inputs AND return value before evaluating.

#### `UnitTokenFromGUID`
- **Documentation File**: `Interface/AddOns/Blizzard_APIDocumentationGenerated/UnitDocumentation.lua`
- **Secret Arguments**: `AllowedWhenTainted` (Throws if tainted execution passes a secret value!)
- **Restriction Trigger**: `SecretWhenUnitIdentityRestricted = true,`

```lua
{
			Name = "UnitTokenFromGUID",
			Type = "Function",
			SecretWhenUnitIdentityRestricted = true,
			SecretArguments = "AllowedWhenTainted",

			Arguments =
			{
				{ Name = "unitGUID", Type = "WOWGUID", Nilable = false },
			},

			Returns =
			{
				{ Name = "unitToken", Type = "string", Nilable = true },
			},
		},
```

**Combat Lockdown Behavior & TacoTip Rule**:
- *Risk*: `SecretArguments = "AllowedWhenUntainted"`.
- *Defense*: Check `isSecretValue` and guard with `pcall`.

### Unit Identity & Character Metadata

#### `UnitGUID`
- **Documentation File**: `Interface/AddOns/Blizzard_APIDocumentationGenerated/UnitDocumentation.lua`
- **Secret Arguments**: `AllowedWhenUntainted` (Throws if tainted execution passes a secret value!)
- **Restriction Trigger**: `SecretWhenUnitIdentityRestricted = true,`

```lua
{
			Name = "UnitGUID",
			Type = "Function",
			SecretWhenUnitIdentityRestricted = true,
			SecretArguments = "AllowedWhenUntainted",

			Arguments =
			{
				{ Name = "unit", Type = "UnitTokenPvPRestrictedForAddOns", Nilable = false },
			},

			Returns =
			{
				{ Name = "result", Type = "WOWGUID", Nilable = true },
			},
		},
```

**Combat Lockdown Behavior & TacoTip Rule**:
- *Risk*: `SecretArguments = "AllowedWhenUntainted"`.
- *Defense*: Check `isSecretValue` and guard with `pcall`.

#### `UnitName`
- **Documentation File**: `Interface/AddOns/Blizzard_APIDocumentationGenerated/UnitDocumentation.lua`
- **Secret Arguments**: `AllowedWhenTainted` (Throws if tainted execution passes a secret value!)
- **Restriction Trigger**: `SecretWhenUnitNameIdentityRestricted = true,`

```lua
{
			Name = "UnitName",
			Type = "Function",
			SecretWhenUnitNameIdentityRestricted = true,
			SecretArguments = "AllowedWhenTainted",

			Arguments =
			{
				{ Name = "unit", Type = "UnitToken", Nilable = false },
			},

			Returns =
			{
				{ Name = "unitName", Type = "cstring", Nilable = false },
				{ Name = "unitServer", Type = "cstring", Nilable = false },
			},
		},
```

**Combat Lockdown Behavior & TacoTip Rule**:
- *Risk*: `SecretArguments = "AllowedWhenUntainted"`.
- *Defense*: Check `isSecretValue` and guard with `pcall`.

#### `UnitPVPName`
- **Documentation File**: `Interface/AddOns/Blizzard_APIDocumentationGenerated/UnitDocumentation.lua`
- **Secret Arguments**: `AllowedWhenUntainted` (Throws if tainted execution passes a secret value!)
- **Restriction Trigger**: `SecretWhenUnitIdentityRestricted = true,`

```lua
{
			Name = "UnitPVPName",
			Type = "Function",
			SecretWhenUnitIdentityRestricted = true,
			SecretArguments = "AllowedWhenUntainted",

			Arguments =
			{
				{ Name = "unit", Type = "UnitToken", Nilable = false },
			},

			Returns =
			{
				{ Name = "result", Type = "string", Nilable = false },
			},
		},
```

**Combat Lockdown Behavior & TacoTip Rule**:
- *Risk*: `SecretArguments = "AllowedWhenUntainted"`.
- *Defense*: Check `isSecretValue` and guard with `pcall`.

#### `UnitClass`
- **Documentation File**: `Interface/AddOns/Blizzard_APIDocumentationGenerated/UnitDocumentation.lua`
- **Secret Arguments**: `AllowedWhenUntainted` (Throws if tainted execution passes a secret value!)
- **Restriction Trigger**: `SecretWhenUnitIdentityRestricted = true,`
- **Restriction Trigger**: `{ Name = "className", Type = "cstring", Nilable = false, ConditionalSecret = true },`

```lua
{
			Name = "UnitClass",
			Type = "Function",
			MayReturnNothing = true,
			SecretWhenUnitIdentityRestricted = true,
			SecretArguments = "AllowedWhenUntainted",

			Arguments =
			{
				{ Name = "unit", Type = "UnitToken", Nilable = false },
			},

			Returns =
			{
				{ Name = "className", Type = "cstring", Nilable = false, ConditionalSecret = true },
				{ Name = "classFilename", Type = "cstring", Nilable = false },
				{ Name = "classID", Type = "number", Nilable = false },
			},
		},
```

**Combat Lockdown Behavior & TacoTip Rule**:
- *Risk*: `SecretArguments = "AllowedWhenUntainted"`.
- *Defense*: Check `isSecretValue` and guard with `pcall`.

#### `UnitRace`
- **Documentation File**: `Interface/AddOns/Blizzard_APIDocumentationGenerated/UnitDocumentation.lua`
- **Secret Arguments**: `AllowedWhenUntainted` (Throws if tainted execution passes a secret value!)
- **Restriction Trigger**: `SecretWhenUnitIdentityRestricted = true,`

```lua
{
			Name = "UnitRace",
			Type = "Function",
			MayReturnNothing = true,
			SecretWhenUnitIdentityRestricted = true,
			SecretArguments = "AllowedWhenUntainted",

			Arguments =
			{
				{ Name = "unit", Type = "UnitToken", Nilable = false },
			},

			Returns =
			{
				{ Name = "localizedRaceName", Type = "cstring", Nilable = false },
				{ Name = "englishRaceName", Type = "cstring", Nilable = false },
				{ Name = "raceID", Type = "number", Nilable = false },
			},
		},
```

**Combat Lockdown Behavior & TacoTip Rule**:
- *Risk*: `SecretArguments = "AllowedWhenUntainted"`.
- *Defense*: Check `isSecretValue` and guard with `pcall`.

#### `UnitSex`
- **Documentation File**: `Interface/AddOns/Blizzard_APIDocumentationGenerated/UnitSexConstantsDocumentation.lua`

```lua
{
			Name = "UnitSex",
			Type = "Enumeration",
			NumValues = 5,
			MinValue = 0,
			MaxValue = 4,
			Fields =
			{
				{ Name = "Male", Type = "UnitSex", EnumValue = 0 },
				{ Name = "Female", Type = "UnitSex", EnumValue = 1 },
				{ Name = "None", Type = "UnitSex", EnumValue = 2 },
				{ Name = "Both", Type = "UnitSex", EnumValue = 3 },
				{ Name = "Neutral", Type = "UnitSex", EnumValue = 4 },
			},
		},
```

**Combat Lockdown Behavior & TacoTip Rule**:
- *Risk*: `SecretArguments = "AllowedWhenUntainted"`.
- *Defense*: Check `isSecretValue` and guard with `pcall`.

#### `UnitLevel`
- **Documentation File**: `Interface/AddOns/Blizzard_APIDocumentationGenerated/UnitDocumentation.lua`
- **Secret Arguments**: `AllowedWhenUntainted` (Throws if tainted execution passes a secret value!)

```lua
{
			Name = "UnitLevel",
			Type = "Function",
			SecretArguments = "AllowedWhenUntainted",

			Arguments =
			{
				{ Name = "name", Type = "cstring", Nilable = false },
			},

			Returns =
			{
				{ Name = "result", Type = "number", Nilable = false },
			},
		},
```

**Combat Lockdown Behavior & TacoTip Rule**:
- *Risk*: `SecretArguments = "AllowedWhenUntainted"`.
- *Defense*: Check `isSecretValue` and guard with `pcall`.

#### `UnitClassification`
- **Documentation File**: `Interface/AddOns/Blizzard_APIDocumentationGenerated/UnitDocumentation.lua`
- **Secret Arguments**: `AllowedWhenUntainted` (Throws if tainted execution passes a secret value!)

```lua
{
			Name = "UnitClassification",
			Type = "Function",
			SecretArguments = "AllowedWhenUntainted",

			Arguments =
			{
				{ Name = "unit", Type = "UnitToken", Nilable = false },
			},

			Returns =
			{
				{ Name = "result", Type = "cstring", Nilable = false },
			},
		},
```

**Combat Lockdown Behavior & TacoTip Rule**:
- *Risk*: `SecretArguments = "AllowedWhenUntainted"`.
- *Defense*: Check `isSecretValue` and guard with `pcall`.

#### `UnitFactionGroup`
- **Documentation File**: `Interface/AddOns/Blizzard_APIDocumentationGenerated/UnitDocumentation.lua`
- **Secret Arguments**: `AllowedWhenUntainted` (Throws if tainted execution passes a secret value!)

```lua
{
			Name = "UnitFactionGroup",
			Type = "Function",
			SecretArguments = "AllowedWhenUntainted",

			Arguments =
			{
				{ Name = "unitName", Type = "cstring", Nilable = false },
				{ Name = "checkDisplayRace", Type = "bool", Nilable = false, Default = false },
			},

			Returns =
			{
				{ Name = "factionGroupTag", Type = "cstring", Nilable = false },
				{ Name = "localized", Type = "cstring", Nilable = false },
			},
		},
```

**Combat Lockdown Behavior & TacoTip Rule**:
- *Risk*: `SecretArguments = "AllowedWhenUntainted"`.
- *Defense*: Check `isSecretValue` and guard with `pcall`.

### Group & Relationship Queries

#### `UnitInParty`
- **Documentation File**: `Interface/AddOns/Blizzard_APIDocumentationGenerated/UnitDocumentation.lua`
- **Secret Arguments**: `AllowedWhenUntainted` (Throws if tainted execution passes a secret value!)

```lua
{
			Name = "UnitInParty",
			Type = "Function",
			SecretArguments = "AllowedWhenUntainted",

			Arguments =
			{
				{ Name = "unit", Type = "UnitToken", Nilable = true },
				{ Name = "partyIndex", Type = "luaIndex", Nilable = true },
			},

			Returns =
			{
				{ Name = "result", Type = "bool", Nilable = false },
			},
		},
```

**Combat Lockdown Behavior & TacoTip Rule**:
- *Risk*: `UnitInRaid` has `SecretWhenUnitIdentityRestricted = true`. In instance combat, return is a secret value. Comparing `resR ~= nil and resR ~= false` throws secret boolean error.
- *Defense*: Must use `safeUnitInParty(unit)` and `safeUnitInRaid(unit)`.

#### `UnitInRaid`
- **Documentation File**: `Interface/AddOns/Blizzard_APIDocumentationGenerated/UnitDocumentation.lua`
- **Secret Arguments**: `AllowedWhenUntainted` (Throws if tainted execution passes a secret value!)
- **Restriction Trigger**: `SecretWhenUnitIdentityRestricted = true,`

```lua
{
			Name = "UnitInRaid",
			Type = "Function",
			SecretWhenUnitIdentityRestricted = true,
			SecretArguments = "AllowedWhenUntainted",

			Arguments =
			{
				{ Name = "unit", Type = "UnitToken", Nilable = true },
				{ Name = "partyIndex", Type = "luaIndex", Nilable = true },
			},

			Returns =
			{
				{ Name = "result", Type = "luaIndex", Nilable = true },
			},
		},
```

**Combat Lockdown Behavior & TacoTip Rule**:
- *Risk*: `UnitInRaid` has `SecretWhenUnitIdentityRestricted = true`. In instance combat, return is a secret value. Comparing `resR ~= nil and resR ~= false` throws secret boolean error.
- *Defense*: Must use `safeUnitInParty(unit)` and `safeUnitInRaid(unit)`.

#### `UnitIsEnemy`
- **Documentation File**: `Interface/AddOns/Blizzard_APIDocumentationGenerated/UnitDocumentation.lua`
- **Secret Arguments**: `AllowedWhenUntainted` (Throws if tainted execution passes a secret value!)

```lua
{
			Name = "UnitIsEnemy",
			Type = "Function",
			SecretArguments = "AllowedWhenUntainted",

			Arguments =
			{
				{ Name = "unit", Type = "UnitToken", Nilable = false },
				{ Name = "target", Type = "UnitToken", Nilable = false },
			},

			Returns =
			{
				{ Name = "result", Type = "bool", Nilable = false },
			},
		},
```

**Combat Lockdown Behavior & TacoTip Rule**:
- *Risk*: `SecretArguments = "AllowedWhenUntainted"`.
- *Defense*: Check `isSecretValue` and guard with `pcall`.

#### `UnitIsFriend`
- **Documentation File**: `Interface/AddOns/Blizzard_APIDocumentationGenerated/UnitDocumentation.lua`
- **Secret Arguments**: `AllowedWhenUntainted` (Throws if tainted execution passes a secret value!)

```lua
{
			Name = "UnitIsFriend",
			Type = "Function",
			SecretArguments = "AllowedWhenUntainted",

			Arguments =
			{
				{ Name = "unit", Type = "UnitToken", Nilable = false },
				{ Name = "target", Type = "UnitToken", Nilable = false },
			},

			Returns =
			{
				{ Name = "result", Type = "bool", Nilable = false },
			},
		},
```

**Combat Lockdown Behavior & TacoTip Rule**:
- *Risk*: `SecretArguments = "AllowedWhenUntainted"`.
- *Defense*: Check `isSecretValue` and guard with `pcall`.

#### `UnitCanAttack`
- **Documentation File**: `Interface/AddOns/Blizzard_APIDocumentationGenerated/UnitDocumentation.lua`
- **Secret Arguments**: `AllowedWhenUntainted` (Throws if tainted execution passes a secret value!)

```lua
{
			Name = "UnitCanAttack",
			Type = "Function",
			SecretArguments = "AllowedWhenUntainted",

			Arguments =
			{
				{ Name = "unit", Type = "UnitToken", Nilable = false },
				{ Name = "target", Type = "UnitToken", Nilable = false },
			},

			Returns =
			{
				{ Name = "result", Type = "bool", Nilable = false },
			},
		},
```

**Combat Lockdown Behavior & TacoTip Rule**:
- *Risk*: `SecretArguments = "AllowedWhenUntainted"`.
- *Defense*: Check `isSecretValue` and guard with `pcall`.

#### `UnitIsSameServer`
- **Documentation File**: `Interface/AddOns/Blizzard_APIDocumentationGenerated/UnitDocumentation.lua`
- **Secret Arguments**: `AllowedWhenUntainted` (Throws if tainted execution passes a secret value!)

```lua
{
			Name = "UnitIsSameServer",
			Type = "Function",
			SecretArguments = "AllowedWhenUntainted",

			Arguments =
			{
				{ Name = "unitName", Type = "cstring", Nilable = false },
			},

			Returns =
			{
				{ Name = "result", Type = "bool", Nilable = false },
			},
		},
```

**Combat Lockdown Behavior & TacoTip Rule**:
- *Risk*: `SecretArguments = "AllowedWhenUntainted"`.
- *Defense*: Check `isSecretValue` and guard with `pcall`.

#### `UnitGroupRolesAssigned`
- **Documentation File**: `Interface/AddOns/Blizzard_APIDocumentationGenerated/UnitDocumentation.lua`
- **Secret Arguments**: `AllowedWhenUntainted` (Throws if tainted execution passes a secret value!)
- **Restriction Trigger**: `SecretWhenUnitIdentityRestricted = true,`

```lua
{
			Name = "UnitGroupRolesAssigned",
			Type = "Function",
			SecretWhenUnitIdentityRestricted = true,
			SecretArguments = "AllowedWhenUntainted",

			Arguments =
			{
				{ Name = "unit", Type = "UnitToken", Nilable = true },
			},

			Returns =
			{
				{ Name = "result", Type = "cstring", Nilable = false },
			},
		},
```

**Combat Lockdown Behavior & TacoTip Rule**:
- *Risk*: `SecretArguments = "AllowedWhenUntainted"`.
- *Defense*: Check `isSecretValue` and guard with `pcall`.

#### `UnitIsOtherPlayersPet`
- **Documentation File**: `Interface/AddOns/Blizzard_APIDocumentationGenerated/UnitDocumentation.lua`
- **Secret Arguments**: `AllowedWhenUntainted` (Throws if tainted execution passes a secret value!)

```lua
{
			Name = "UnitIsOtherPlayersPet",
			Type = "Function",
			SecretArguments = "AllowedWhenUntainted",

			Arguments =
			{
				{ Name = "unit", Type = "UnitToken", Nilable = true },
			},

			Returns =
			{
				{ Name = "result", Type = "bool", Nilable = false },
			},
		},
```

**Combat Lockdown Behavior & TacoTip Rule**:
- *Risk*: `SecretArguments = "AllowedWhenUntainted"`.
- *Defense*: Check `isSecretValue` and guard with `pcall`.

#### `UnitReaction`
- **Documentation File**: `Interface/AddOns/Blizzard_APIDocumentationGenerated/UnitDocumentation.lua`
- **Secret Arguments**: `AllowedWhenUntainted` (Throws if tainted execution passes a secret value!)

```lua
{
			Name = "UnitReaction",
			Type = "Function",
			SecretArguments = "AllowedWhenUntainted",

			Arguments =
			{
				{ Name = "unit", Type = "UnitToken", Nilable = false },
				{ Name = "target", Type = "UnitToken", Nilable = false },
			},

			Returns =
			{
				{ Name = "result", Type = "luaIndex", Nilable = true },
			},
		},
```

**Combat Lockdown Behavior & TacoTip Rule**:
- *Risk*: `SecretArguments = "AllowedWhenUntainted"`.
- *Defense*: Check `isSecretValue` and guard with `pcall`.

### Vitals, Status & Power

#### `UnitHealth`
- **Documentation File**: `Interface/AddOns/Blizzard_APIDocumentationGenerated/UnitDocumentation.lua`
- **Secret Arguments**: `AllowedWhenUntainted` (Throws if tainted execution passes a secret value!)
- **Secret Returns**: `true` (Always returns secret value in restricted contexts)

```lua
{
			Name = "UnitHealth",
			Type = "Function",
			SecretReturns = true,
			SecretArguments = "AllowedWhenUntainted",

			Arguments =
			{
				{ Name = "unit", Type = "UnitTokenPvPRestrictedForAddOns", Nilable = false },
				{ Name = "usePredicted", Type = "bool", Nilable = false, Default = true },
			},

			Returns =
			{
				{ Name = "result", Type = "number", Nilable = false },
			},
		},
```

**Combat Lockdown Behavior & TacoTip Rule**:
- *Risk*: Return values are secret numbers in restricted combat. Status bars (`SetMinMaxValues`, `SetValue`) accept secret numbers directly, but Lua comparisons (`max > 0`, `cur == max`) throw.
- *Defense*: Pass values straight to status bar without Lua arithmetic or comparison.

#### `UnitHealthMax`
- **Documentation File**: `Interface/AddOns/Blizzard_APIDocumentationGenerated/UnitDocumentation.lua`
- **Secret Arguments**: `AllowedWhenUntainted` (Throws if tainted execution passes a secret value!)
- **Restriction Trigger**: `SecretWhenUnitHealthMaxRestricted = true,`

```lua
{
			Name = "UnitHealthMax",
			Type = "Function",
			SecretWhenUnitHealthMaxRestricted = true,
			SecretArguments = "AllowedWhenUntainted",

			Arguments =
			{
				{ Name = "unit", Type = "UnitTokenPvPRestrictedForAddOns", Nilable = false },
			},

			Returns =
			{
				{ Name = "result", Type = "number", Nilable = false },
			},
		},
```

**Combat Lockdown Behavior & TacoTip Rule**:
- *Risk*: Return values are secret numbers in restricted combat. Status bars (`SetMinMaxValues`, `SetValue`) accept secret numbers directly, but Lua comparisons (`max > 0`, `cur == max`) throw.
- *Defense*: Pass values straight to status bar without Lua arithmetic or comparison.

#### `UnitPower`
- **Documentation File**: `Interface/AddOns/Blizzard_APIDocumentationGenerated/UnitDocumentation.lua`
- **Secret Arguments**: `AllowedWhenUntainted` (Throws if tainted execution passes a secret value!)
- **Restriction Trigger**: `SecretWhenUnitPowerRestricted = true,`

```lua
{
			Name = "UnitPower",
			Type = "Function",
			SecretWhenUnitPowerRestricted = true,
			SecretArguments = "AllowedWhenUntainted",

			Arguments =
			{
				{ Name = "unitToken", Type = "UnitTokenPvPRestrictedForAddOns", Nilable = false },
				{ Name = "powerType", Type = "PowerType", Nilable = true },
				{ Name = "unmodified", Type = "bool", Nilable = false, Default = false },
			},

			Returns =
			{
				{ Name = "power", Type = "number", Nilable = false },
			},
		},
```

**Combat Lockdown Behavior & TacoTip Rule**:
- *Risk*: Return values are secret numbers in restricted combat. Status bars (`SetMinMaxValues`, `SetValue`) accept secret numbers directly, but Lua comparisons (`max > 0`, `cur == max`) throw.
- *Defense*: Pass values straight to status bar without Lua arithmetic or comparison.

#### `UnitPowerMax`
- **Documentation File**: `Interface/AddOns/Blizzard_APIDocumentationGenerated/UnitDocumentation.lua`
- **Secret Arguments**: `AllowedWhenUntainted` (Throws if tainted execution passes a secret value!)
- **Restriction Trigger**: `SecretWhenUnitPowerMaxRestricted = true,`

```lua
{
			Name = "UnitPowerMax",
			Type = "Function",
			SecretWhenUnitPowerMaxRestricted = true,
			SecretArguments = "AllowedWhenUntainted",

			Arguments =
			{
				{ Name = "unitToken", Type = "UnitTokenPvPRestrictedForAddOns", Nilable = false },
				{ Name = "powerType", Type = "PowerType", Nilable = true },
				{ Name = "unmodified", Type = "bool", Nilable = false, Default = false },
			},

			Returns =
			{
				{ Name = "maxPower", Type = "number", Nilable = false },
			},
		},
```

**Combat Lockdown Behavior & TacoTip Rule**:
- *Risk*: Return values are secret numbers in restricted combat. Status bars (`SetMinMaxValues`, `SetValue`) accept secret numbers directly, but Lua comparisons (`max > 0`, `cur == max`) throw.
- *Defense*: Pass values straight to status bar without Lua arithmetic or comparison.

#### `UnitPowerType`
- **Documentation File**: `Interface/AddOns/Blizzard_APIDocumentationGenerated/UnitDocumentation.lua`
- **Secret Arguments**: `AllowedWhenUntainted` (Throws if tainted execution passes a secret value!)

```lua
{
			Name = "UnitPowerType",
			Type = "Function",
			MayReturnNothing = true,
			SecretArguments = "AllowedWhenUntainted",

			Arguments =
			{
				{ Name = "unit", Type = "UnitTokenPvPRestrictedForAddOns", Nilable = false },
				{ Name = "index", Type = "number", Nilable = false, Default = 0 },
			},

			Returns =
			{
				{ Name = "powerType", Type = "PowerType", Nilable = false },
				{ Name = "powerTypeToken", Type = "string", Nilable = false },
				{ Name = "rgbX", Type = "number", Nilable = false },
				{ Name = "rgbY", Type = "number", Nilable = false },
				{ Name = "rgbZ", Type = "number", Nilable = false },
			},
		},
```

**Combat Lockdown Behavior & TacoTip Rule**:
- *Risk*: `SecretArguments = "AllowedWhenUntainted"`.
- *Defense*: Check `isSecretValue` and guard with `pcall`.

#### `UnitIsDead`
- **Documentation File**: `Interface/AddOns/Blizzard_APIDocumentationGenerated/UnitDocumentation.lua`
- **Secret Arguments**: `AllowedWhenUntainted` (Throws if tainted execution passes a secret value!)

```lua
{
			Name = "UnitIsDead",
			Type = "Function",
			SecretArguments = "AllowedWhenUntainted",

			Arguments =
			{
				{ Name = "unit", Type = "UnitToken", Nilable = false },
			},

			Returns =
			{
				{ Name = "result", Type = "bool", Nilable = false },
			},
		},
```

**Combat Lockdown Behavior & TacoTip Rule**:
- *Risk*: `SecretArguments = "AllowedWhenUntainted"`.
- *Defense*: Check `isSecretValue` and guard with `pcall`.

#### `UnitIsGhost`
- **Documentation File**: `Interface/AddOns/Blizzard_APIDocumentationGenerated/UnitDocumentation.lua`
- **Secret Arguments**: `AllowedWhenUntainted` (Throws if tainted execution passes a secret value!)

```lua
{
			Name = "UnitIsGhost",
			Type = "Function",
			SecretArguments = "AllowedWhenUntainted",

			Arguments =
			{
				{ Name = "unit", Type = "UnitToken", Nilable = false },
			},

			Returns =
			{
				{ Name = "result", Type = "bool", Nilable = false },
			},
		},
```

**Combat Lockdown Behavior & TacoTip Rule**:
- *Risk*: `SecretArguments = "AllowedWhenUntainted"`.
- *Defense*: Check `isSecretValue` and guard with `pcall`.

#### `UnitIsFeignDeath`
- **Documentation File**: `Interface/AddOns/Blizzard_APIDocumentationGenerated/UnitDocumentation.lua`
- **Secret Arguments**: `AllowedWhenUntainted` (Throws if tainted execution passes a secret value!)

```lua
{
			Name = "UnitIsFeignDeath",
			Type = "Function",
			SecretArguments = "AllowedWhenUntainted",

			Arguments =
			{
				{ Name = "unit", Type = "UnitToken", Nilable = false },
			},

			Returns =
			{
				{ Name = "result", Type = "bool", Nilable = false },
			},
		},
```

**Combat Lockdown Behavior & TacoTip Rule**:
- *Risk*: `SecretArguments = "AllowedWhenUntainted"`.
- *Defense*: Check `isSecretValue` and guard with `pcall`.

#### `UnitIsConnected`
- **Documentation File**: `Interface/AddOns/Blizzard_APIDocumentationGenerated/UnitDocumentation.lua`
- **Secret Arguments**: `AllowedWhenUntainted` (Throws if tainted execution passes a secret value!)

```lua
{
			Name = "UnitIsConnected",
			Type = "Function",
			SecretArguments = "AllowedWhenUntainted",

			Arguments =
			{
				{ Name = "unit", Type = "UnitToken", Nilable = false },
			},

			Returns =
			{
				{ Name = "isConnected", Type = "bool", Nilable = false },
			},
		},
```

**Combat Lockdown Behavior & TacoTip Rule**:
- *Risk*: `SecretArguments = "AllowedWhenUntainted"`.
- *Defense*: Check `isSecretValue` and guard with `pcall`.

#### `UnitIsPVP`
- **Documentation File**: `Interface/AddOns/Blizzard_APIDocumentationGenerated/UnitDocumentation.lua`
- **Secret Arguments**: `AllowedWhenUntainted` (Throws if tainted execution passes a secret value!)
- **Restriction Trigger**: `SecretWhenUnitIdentityRestricted = true,`

```lua
{
			Name = "UnitIsPVP",
			Type = "Function",
			SecretWhenUnitIdentityRestricted = true,
			SecretArguments = "AllowedWhenUntainted",

			Arguments =
			{
				{ Name = "unit", Type = "UnitToken", Nilable = false },
			},

			Returns =
			{
				{ Name = "result", Type = "bool", Nilable = false },
			},
		},
```

**Combat Lockdown Behavior & TacoTip Rule**:
- *Risk*: `SecretWhenUnitIdentityRestricted = true`. Returns a secret boolean. `if UnitIsPVP(unit) then` throws.
- *Defense*: Must wrap in `safeUnitIsPVP(unit)`.

#### `UnitIsAFK`
- **Documentation File**: `Interface/AddOns/Blizzard_APIDocumentationGenerated/UnitDocumentation.lua`
- **Secret Arguments**: `AllowedWhenUntainted` (Throws if tainted execution passes a secret value!)
- **Restriction Trigger**: `SecretInChatMessagingLockdown = true,`

```lua
{
			Name = "UnitIsAFK",
			Type = "Function",
			SecretInChatMessagingLockdown = true,
			SecretArguments = "AllowedWhenUntainted",

			Arguments =
			{
				{ Name = "unit", Type = "UnitToken", Nilable = false },
			},

			Returns =
			{
				{ Name = "result", Type = "bool", Nilable = false },
			},
		},
```

**Combat Lockdown Behavior & TacoTip Rule**:
- *Risk*: `SecretArguments = "AllowedWhenUntainted"`.
- *Defense*: Check `isSecretValue` and guard with `pcall`.

#### `UnitIsDND`
- **Documentation File**: `Interface/AddOns/Blizzard_APIDocumentationGenerated/UnitDocumentation.lua`
- **Secret Arguments**: `AllowedWhenUntainted` (Throws if tainted execution passes a secret value!)
- **Restriction Trigger**: `SecretInChatMessagingLockdown = true,`

```lua
{
			Name = "UnitIsDND",
			Type = "Function",
			SecretInChatMessagingLockdown = true,
			SecretArguments = "AllowedWhenUntainted",

			Arguments =
			{
				{ Name = "unit", Type = "UnitToken", Nilable = false },
			},

			Returns =
			{
				{ Name = "result", Type = "bool", Nilable = false },
			},
		},
```

**Combat Lockdown Behavior & TacoTip Rule**:
- *Risk*: `SecretArguments = "AllowedWhenUntainted"`.
- *Defense*: Check `isSecretValue` and guard with `pcall`.

#### `UnitIsVisible`
- **Documentation File**: `Interface/AddOns/Blizzard_APIDocumentationGenerated/UnitDocumentation.lua`
- **Secret Arguments**: `AllowedWhenUntainted` (Throws if tainted execution passes a secret value!)

```lua
{
			Name = "UnitIsVisible",
			Type = "Function",
			SecretArguments = "AllowedWhenUntainted",

			Arguments =
			{
				{ Name = "unit", Type = "UnitToken", Nilable = true },
			},

			Returns =
			{
				{ Name = "result", Type = "bool", Nilable = false },
			},
		},
```

**Combat Lockdown Behavior & TacoTip Rule**:
- *Risk*: `SecretArguments = "AllowedWhenUntainted"`.
- *Defense*: Check `isSecretValue` and guard with `pcall`.

#### `UnitDistanceSquared`
- **Documentation File**: `Interface/AddOns/Blizzard_APIDocumentationGenerated/UnitDocumentation.lua`
- **Secret Arguments**: `AllowedWhenUntainted` (Throws if tainted execution passes a secret value!)

```lua
{
			Name = "UnitDistanceSquared",
			Type = "Function",
			SecretArguments = "AllowedWhenUntainted",

			Arguments =
			{
				{ Name = "unit", Type = "UnitToken", Nilable = false },
			},

			Returns =
			{
				{ Name = "distance", Type = "number", Nilable = false },
				{ Name = "checkedDistance", Type = "bool", Nilable = false },
			},
		},
```

**Combat Lockdown Behavior & TacoTip Rule**:
- *Risk*: `SecretArguments = "AllowedWhenUntainted"`.
- *Defense*: Check `isSecretValue` and guard with `pcall`.

### Inspection & Distance

#### `CanInspect`
- **Documentation File**: `Interface/AddOns/Blizzard_APIDocumentationGenerated/PlayerScriptDocumentation.lua`
- **Secret Arguments**: `AllowedWhenUntainted` (Throws if tainted execution passes a secret value!)

```lua
{
			Name = "CanInspect",
			Type = "Function",
			SecretArguments = "AllowedWhenUntainted",

			Arguments =
			{
				{ Name = "targetGUID", Type = "UnitToken", Nilable = false },
			},

			Returns =
			{
				{ Name = "result", Type = "bool", Nilable = false },
			},
		},
```

**Combat Lockdown Behavior & TacoTip Rule**:
- *Risk*: `SecretArguments = "AllowedWhenUntainted"`.
- *Defense*: Check `isSecretValue` and guard with `pcall`.

#### `CheckInteractDistance`
- **Documentation File**: `Interface/AddOns/Blizzard_APIDocumentationGenerated/PlayerScriptDocumentation.lua`
- **Secret Arguments**: `AllowedWhenUntainted` (Throws if tainted execution passes a secret value!)

```lua
{
			Name = "CheckInteractDistance",
			Type = "Function",
			SecretArguments = "AllowedWhenUntainted",

			Arguments =
			{
				{ Name = "unitGUID", Type = "UnitToken", Nilable = false },
				{ Name = "distIndex", Type = "luaIndex", Nilable = false },
			},

			Returns =
			{
				{ Name = "result", Type = "bool", Nilable = false },
			},
		},
```

**Combat Lockdown Behavior & TacoTip Rule**:
- *Risk*: `SecretArguments = "AllowedWhenUntainted"`.
- *Defense*: Check `isSecretValue` and guard with `pcall`.

#### `NotifyInspect`
- **Documentation File**: `Interface/AddOns/Blizzard_APIDocumentationGenerated/PlayerScriptDocumentation.lua`
- **Secret Arguments**: `AllowedWhenUntainted` (Throws if tainted execution passes a secret value!)

```lua
{
			Name = "NotifyInspect",
			Type = "Function",
			SecretArguments = "AllowedWhenUntainted",

			Arguments =
			{
				{ Name = "targetGUID", Type = "UnitToken", Nilable = false },
			},
		},
```

**Combat Lockdown Behavior & TacoTip Rule**:
- *Risk*: `SecretArguments = "AllowedWhenUntainted"`.
- *Defense*: Check `isSecretValue` and guard with `pcall`.

### Map & Zone Positioning

#### `GetBestMapForUnit`
- **Documentation File**: `Interface/AddOns/Blizzard_APIDocumentationGenerated/MapDocumentation.lua`
- **Secret Arguments**: `AllowedWhenUntainted` (Throws if tainted execution passes a secret value!)

```lua
{
			Name = "GetBestMapForUnit",
			Type = "Function",
			SecretArguments = "AllowedWhenUntainted",
			Documentation = { "Only works for the player and party members." },

			Arguments =
			{
				{ Name = "unitToken", Type = "UnitToken", Nilable = false },
			},

			Returns =
			{
				{ Name = "uiMapID", Type = "number", Nilable = true },
			},
		},
```

**Combat Lockdown Behavior & TacoTip Rule**:
- *Risk*: `SecretArguments = "AllowedWhenUntainted"`.
- *Defense*: Check `isSecretValue` and guard with `pcall`.

#### `GetMapInfo`
- **Documentation File**: `Interface/AddOns/Blizzard_APIDocumentationGenerated/MapDocumentation.lua`
- **Secret Arguments**: `AllowedWhenUntainted` (Throws if tainted execution passes a secret value!)

```lua
{
			Name = "GetMapInfo",
			Type = "Function",
			MayReturnNothing = true,
			SecretArguments = "AllowedWhenUntainted",

			Arguments =
			{
				{ Name = "uiMapID", Type = "number", Nilable = false },
			},

			Returns =
			{
				{ Name = "info", Type = "UiMapDetails", Nilable = false },
			},
		},
```

**Combat Lockdown Behavior & TacoTip Rule**:
- *Risk*: `SecretArguments = "AllowedWhenUntainted"`.
- *Defense*: Check `isSecretValue` and guard with `pcall`.

### Specialization & Talents (Camelot / Forever)

#### `GetSpecialization`
- **Documentation File**: `Interface/AddOns/Blizzard_APIDocumentationGenerated/SpecializationInfoDocumentation.lua`
- **Secret Arguments**: `AllowedWhenUntainted` (Throws if tainted execution passes a secret value!)

```lua
{
			Name = "GetSpecialization",
			Type = "Function",
			SecretArguments = "AllowedWhenUntainted",

			Arguments =
			{
				{ Name = "isInspect", Type = "bool", Nilable = true },
				{ Name = "isPet", Type = "bool", Nilable = true },
				{ Name = "specGroupIndex", Type = "luaIndex", Nilable = true },
			},

			Returns =
			{
				{ Name = "specializationIndex", Type = "luaIndex", Nilable = false },
			},
		},
```

**Combat Lockdown Behavior & TacoTip Rule**:
- *Risk*: `SecretArguments = "AllowedWhenUntainted"`.
- *Defense*: Check `isSecretValue` and guard with `pcall`.

#### `GetSpecializationInfo`
- **Documentation File**: `Interface/AddOns/Blizzard_APIDocumentationGenerated/SpecializationInfoDocumentation.lua`
- **Secret Arguments**: `AllowedWhenUntainted` (Throws if tainted execution passes a secret value!)

```lua
{
			Name = "GetSpecializationInfo",
			Type = "Function",
			SecretArguments = "AllowedWhenUntainted",

			Arguments =
			{
				{ Name = "specializationIndex", Type = "luaIndex", Nilable = false },
				{ Name = "isInspect", Type = "bool", Nilable = false, Default = false },
				{ Name = "isPet", Type = "bool", Nilable = false, Default = false },
				{ Name = "inspectTarget", Type = "string", Nilable = true },
				{ Name = "sex", Type = "number", Nilable = true },
				{ Name = "groupIndex", Type = "luaIndex", Nilable = true },
				{ Name = "classID", Type = "number", Nilable = true },
			},

			Returns =
			{
				{ Name = "specId", Type = "number", Nilable = false, Default = 0 },
				{ Name = "name", Type = "string", Nilable = true },
				{ Name = "description", Type = "string", Nilable = true },
				{ Name = "icon", Type = "fileID", Nilable = true },
				{ Name = "role", Type = "string", Nilable = true },
				{ Name = "primaryStat", Type = "luaIndex", Nilable = true },
				{ Name = "pointsSpent", Type = "number", Nilable = false, Default = 0 },
				{ Name = "background", Type = "string", Nilable = true },
				{ Name = "previewPointsSpent", Type = "number", Nilable = false, Default = 0 },
				{ Name = "isUnlocked", Type = "bool", Nilable = false, Default = true },
			},
		},
```

**Combat Lockdown Behavior & TacoTip Rule**:
- *Risk*: `SecretArguments = "AllowedWhenUntainted"`.
- *Defense*: Check `isSecretValue` and guard with `pcall`.

### Tooltip & Loot APIs

#### `GetLootItem`
- **Documentation File**: `Interface/AddOns/Blizzard_APIDocumentationGenerated/TooltipInfoDocumentation.lua`
- **Secret Arguments**: `AllowedWhenUntainted` (Throws if tainted execution passes a secret value!)

```lua
{
			Name = "GetLootItem",
			Type = "Function",
			MayReturnNothing = true,
			SecretArguments = "AllowedWhenUntainted",

			Arguments =
			{
				{ Name = "slot", Type = "luaIndex", Nilable = false },
			},

			Returns =
			{
				{ Name = "data", Type = "TooltipData", Nilable = false },
			},
		},
```

**Combat Lockdown Behavior & TacoTip Rule**:
- *Risk*: Loot items before distribution contain secret lines. Taint reaching `ProcessInfo` causes tooltip lines to drop or vanish.
- *Defense*: Detect all loot frame owners (`GroupLootFrame1..4`, `BonusRollFrame`, `LootFrame`) and leave tooltips completely native.

#### `GetLootRollItem`
- **Documentation File**: `Interface/AddOns/Blizzard_APIDocumentationGenerated/TooltipInfoDocumentation.lua`
- **Secret Arguments**: `AllowedWhenUntainted` (Throws if tainted execution passes a secret value!)

```lua
{
			Name = "GetLootRollItem",
			Type = "Function",
			MayReturnNothing = true,
			SecretArguments = "AllowedWhenUntainted",

			Arguments =
			{
				{ Name = "id", Type = "number", Nilable = false },
			},

			Returns =
			{
				{ Name = "data", Type = "TooltipData", Nilable = false },
			},
		},
```

**Combat Lockdown Behavior & TacoTip Rule**:
- *Risk*: Loot items before distribution contain secret lines. Taint reaching `ProcessInfo` causes tooltip lines to drop or vanish.
- *Defense*: Detect all loot frame owners (`GroupLootFrame1..4`, `BonusRollFrame`, `LootFrame`) and leave tooltips completely native.

#### `GetHyperlink`
- **Documentation File**: `Interface/AddOns/Blizzard_APIDocumentationGenerated/TooltipInfoDocumentation.lua`
- **Secret Arguments**: `AllowedWhenUntainted` (Throws if tainted execution passes a secret value!)

```lua
{
			Name = "GetHyperlink",
			Type = "Function",
			MayReturnNothing = true,
			SecretArguments = "AllowedWhenUntainted",

			Arguments =
			{
				{ Name = "hyperlink", Type = "cstring", Nilable = false },
				{ Name = "optionalArg1", Type = "number", Nilable = true },
				{ Name = "optionalArg2", Type = "number", Nilable = true },
				{ Name = "hideVendorPrice", Type = "bool", Nilable = true },
			},

			Returns =
			{
				{ Name = "data", Type = "TooltipData", Nilable = false },
			},
		},
```

**Combat Lockdown Behavior & TacoTip Rule**:
- *Risk*: `SecretArguments = "AllowedWhenUntainted"`.
- *Defense*: Check `isSecretValue` and guard with `pcall`.

#### `GetUnit`
- **Documentation File**: `Interface/AddOns/Blizzard_APIDocumentationGenerated/TooltipInfoDocumentation.lua`
- **Secret Arguments**: `AllowedWhenUntainted` (Throws if tainted execution passes a secret value!)

```lua
{
			Name = "GetUnit",
			Type = "Function",
			MayReturnNothing = true,
			SecretArguments = "AllowedWhenUntainted",

			Arguments =
			{
				{ Name = "unit", Type = "UnitTokenPvPRestrictedForAddOns", Nilable = false },
				{ Name = "hideStatus", Type = "bool", Nilable = true },
			},

			Returns =
			{
				{ Name = "data", Type = "TooltipData", Nilable = false },
			},
		},
```

**Combat Lockdown Behavior & TacoTip Rule**:
- *Risk*: `SecretArguments = "AllowedWhenUntainted"`.
- *Defense*: Check `isSecretValue` and guard with `pcall`.

---

### Item & Equipment APIs

#### `IsEquippableItem` / `C_Item.IsEquippableItem`
- **Documentation File**: `Interface/AddOns/Blizzard_APIDocumentationGenerated/ItemDocumentation.lua`
- **Secret Arguments**: `AllowedWhenUntainted` (Throws `bad argument #1` if tainted execution queries with a secret link/item)

```lua
{
			Name = "IsEquippableItem",
			Type = "Function",
			SecretArguments = "AllowedWhenUntainted",

			Arguments =
			{
				{ Name = "itemInfo", Type = "ItemInfo", Nilable = false },
			},

			Returns =
			{
				{ Name = "result", Type = "bool", Nilable = false },
			},
		},
```

**Combat Lockdown Behavior & TacoTip Rule**:
- *Risk*: If called bare with a tainted item link or secret item token during instance combat, Blizzard immediately halts execution with `bad argument #1 to 'IsEquippableItem' (Secret values are only allowed during untainted execution)`. Furthermore, the returned boolean may be annotated as a secret boolean.
- *Defense*:
  ```lua
  local okEq, resEq = pcall(IsEquippableItem, itemLink)
  if (okEq and not isSecretValue(resEq) and resEq == true) then
      isEquippable = true
  end
  ```

#### `GetItemInfo` / `C_Item.GetItemInfo`
- **Documentation File**: `Interface/AddOns/Blizzard_APIDocumentationGenerated/ItemDocumentation.lua`
- **Secret Arguments**: `AllowedWhenUntainted` (Throws `bad argument #1` if tainted execution queries with a secret link/item)
- **May Return Nothing**: `true`

```lua
{
			Name = "GetItemInfo",
			Type = "Function",
			MayReturnNothing = true,
			SecretArguments = "AllowedWhenUntainted",

			Arguments =
			{
				{ Name = "itemInfo", Type = "ItemInfo", Nilable = false },
			},

			Returns =
			{
				{ Name = "itemName", Type = "cstring", Nilable = false },
				{ Name = "itemLink", Type = "cstring", Nilable = false },
				{ Name = "itemQuality", Type = "ItemQuality", Nilable = false },
				{ Name = "itemLevel", Type = "number", Nilable = false },
				{ Name = "itemMinLevel", Type = "number", Nilable = false },
				{ Name = "itemType", Type = "cstring", Nilable = false },
				{ Name = "itemSubType", Type = "cstring", Nilable = false },
				{ Name = "itemStackCount", Type = "number", Nilable = false },
				{ Name = "itemEquipLoc", Type = "cstring", Nilable = false },
				{ Name = "itemTexture", Type = "fileID", Nilable = false },
				{ Name = "sellPrice", Type = "number", Nilable = false },
				{ Name = "classID", Type = "number", Nilable = false },
				{ Name = "subclassID", Type = "number", Nilable = false },
				{ Name = "bindType", Type = "number", Nilable = false },
				{ Name = "expacID", Type = "number", Nilable = false },
				{ Name = "setID", Type = "number", Nilable = false },
				{ Name = "isCraftingReagent", Type = "bool", Nilable = false },
			},
		},
```

**Combat Lockdown Behavior & TacoTip Rule**:
- *Risk*: Calling `GetItemInfo(itemLink)` without `pcall` causes an uncaught crash when `itemLink` contains secret data in combat.
- *Defense*:
  ```lua
  local okInfo, iName, iLink, iQual, iLvl, iMinLvl, iType, iSubType, iStack, iEquip, iTex, iPrice, iClassId, iSubClassId, iBind = pcall(getItemInfoFn, itemLink)
  if (okInfo and not isSecretValue(iName)) then
      itemInfo = { iName, iLink, iQual, iLvl, iMinLvl, iType, iSubType, iStack, iEquip, iTex, iPrice, iClassId, iSubClassId, iBind }
  end
  ```

#### `GetItemInfoInstant` / `C_Item.GetItemInfoInstant`
- **Documentation File**: `Interface/AddOns/Blizzard_APIDocumentationGenerated/ItemDocumentation.lua`
- **Secret Arguments**: `AllowedWhenUntainted`

```lua
{
			Name = "GetItemInfoInstant",
			Type = "Function",
			MayReturnNothing = true,
			SecretArguments = "AllowedWhenUntainted",

			Arguments =
			{
				{ Name = "itemInfo", Type = "ItemInfo", Nilable = false },
			},

			Returns =
			{
				{ Name = "itemID", Type = "number", Nilable = false },
				{ Name = "itemType", Type = "cstring", Nilable = false },
				{ Name = "itemSubType", Type = "cstring", Nilable = false },
				{ Name = "itemEquipLoc", Type = "cstring", Nilable = false },
				{ Name = "icon", Type = "fileID", Nilable = false },
				{ Name = "classID", Type = "number", Nilable = false },
				{ Name = "subClassID", Type = "number", Nilable = false },
			},
		},
```

**Combat Lockdown Behavior & TacoTip Rule**:
- *Defense*: Wrap with `pcall` and verify `not isSecretValue(instId) and type(instId) == "number"`.

#### `C_Item.GetItemLinkByGUID`
- **Documentation File**: `Interface/AddOns/Blizzard_APIDocumentationGenerated/ItemDocumentation.lua`
- **Secret Arguments**: `AllowedWhenUntainted`

```lua
{
			Name = "GetItemLinkByGUID",
			Type = "Function",
			SecretArguments = "AllowedWhenUntainted",

			Arguments =
			{
				{ Name = "itemGUID", Type = "WOWGUID", Nilable = false },
			},

			Returns =
			{
				{ Name = "itemLink", Type = "string", Nilable = true },
			},
		},
```

**Combat Lockdown Behavior & TacoTip Rule**:
- *Defense*: Only invoke when `data.guid and not isSecretValue(data.guid)`, wrapped in `pcall`.

#### `C_Item.RequestLoadItemDataByID`
- **Documentation File**: `Interface/AddOns/Blizzard_APIDocumentationGenerated/ItemDocumentation.lua`
- **Secret Arguments**: `AllowedWhenUntainted`

```lua
{
			Name = "RequestLoadItemDataByID",
			Type = "Function",
			SecretArguments = "AllowedWhenUntainted",

			Arguments =
			{
				{ Name = "itemInfo", Type = "ItemInfo", Nilable = false },
			},
		},
```

**Combat Lockdown Behavior & TacoTip Rule**:
- *Defense*: Verify `itemID and not isSecretValue(itemID)` before calling `pcall(RequestLoadItemDataByID, itemID)`.

#### `GetInventoryItemLink`
- **Documentation Scope**: Blizzard C API / `PaperDollFrame.lua`
- **Parameters**: `unit` (UnitToken), `slotID` (number, 1..19)
- **Returns**: `itemLink` (string or nil)

**Combat Lockdown Behavior & TacoTip Rule**:
- *Risk*: Calling `GetInventoryItemLink(unit, slotID)` on a secret unit token or restricted player raises `bad argument #1 ... AllowedWhenUntainted`.
- *Defense*: Wrap with `pcall(getLink, unit, slotID)` and verify `not isSecretValue(rawLink)`.

---

### Specialization & Camelot Trait APIs

#### `C_Traits.GetGroupDisplayInfoByTreeID`
- **Documentation File**: `Interface/AddOns/Blizzard_APIDocumentationGenerated/SharedTraitsDocumentation.lua`
- **Secret Arguments**: `AllowedWhenUntainted`

```lua
{
			Name = "GetGroupDisplayInfoByTreeID",
			Type = "Function",

			Arguments =
			{
				{ Name = "treeID", Type = "number", Nilable = false },
			},

			Returns =
			{
				{ Name = "displayInfos", Type = "table", InnerType = "TraitGroupDisplayInfo", Nilable = false },
			},
		},
```

- **`TraitGroupDisplayInfo` Struct**:
  - `groupID`: number
  - `displayName`: string
  - `icon`: fileID

#### `C_Traits.GetGroupCurrencyInfo`
- **Documentation File**: `Interface/AddOns/Blizzard_APIDocumentationGenerated/SharedTraitsDocumentation.lua`

```lua
{
			Name = "GetGroupCurrencyInfo",
			Type = "Function",

			Arguments =
			{
				{ Name = "configID", Type = "number", Nilable = false },
				{ Name = "groupIDs", Type = "table", InnerType = "number", Nilable = false },
			},

			Returns =
			{
				{ Name = "groupCurrencyInfos", Type = "table", InnerType = "GroupCurrencyInfo", Nilable = false },
			},
		},
```

- **`GroupCurrencyInfo` Struct**:
  - `groupID`: number
  - `spent`: number
  - `spentInTree`: number

#### `C_Traits.HasValidInspectData`
- **Documentation File**: `Interface/AddOns/Blizzard_APIDocumentationGenerated/SharedTraitsDocumentation.lua`

```lua
{
			Name = "HasValidInspectData",
			Type = "Function",

			Returns =
			{
				{ Name = "hasData", Type = "bool", Nilable = false },
			},
		},
```

#### `C_Traits.GetConfigInfo`
- **Documentation File**: `Interface/AddOns/Blizzard_APIDocumentationGenerated/SharedTraitsDocumentation.lua`

```lua
{
			Name = "GetConfigInfo",
			Type = "Function",

			Arguments =
			{
				{ Name = "configID", Type = "number", Nilable = false },
			},

			Returns =
			{
				{ Name = "configInfo", Type = "TraitConfigInfo", Nilable = false },
			},
		},
```

---

---

## 3. Loot Window Native Integrity Architecture

On WoW Forever, loot tooltips for unawarded items contain client-side secret lines.
Blizzard documentation (`GameTooltip.lua:994-1003`) explicitly notes that addon taint in `ProcessInfo` combined with secret line data can cause the client to drop all lines, leaving a blank tooltip.

### Loot Frames Hierarchy & Detection Matrix

| Frame Type | Frame Names / Elements | Owner Object / Properties | Detection Strategy |
| :--- | :--- | :--- | :--- |
| **Corpse Loot** | `LootFrame`, `LootFrameItemElementMixin` | `owner.GetSlotIndex`, `owner.GetItemSlotType` | Function presence on owner |
| **Group Loot Roll** | `GroupLootFrame1` .. `4`, `GroupLootContainer` | `owner.rollID`, `owner:GetParent().rollID` | `rollID ~= nil` on owner or parent |
| **Bonus Roll** | `BonusRollFrame`, `BonusRollLootWonFrame` | Frame name contains `BonusRoll` | Name pattern match |
| **Loot History** | `LootHistoryFrame`, `LootHistoryItem` | Frame name contains `LootHistory` | Name pattern match |
| **Master Looter** | `MasterLooterFrame` | Frame name contains `MasterLoot` | Name pattern match |

When `isForeverLootTooltip(tooltip)` returns `true`:
1. `itemToolTipHook`: Early returns without calling `clearTooltipVisuals`, without querying `C_Item`, and without adding `Item Level`, `GearScore`, or `HunterScore` rows.
2. `onTooltipShow`: Skips `tooltip.GetItem`, `resolveTooltipUnit`, and `TooltipUtil.GetDisplayedUnit` reads.
3. The loot tooltip remains 100% native Blizzard code without taint.

---

## 4. Centralized Safe Helper Standards for TacoTip

```lua
-- Cryptographically safe Secret Value probe:
function TT.isSecretValue(v)
    if (type(v) == "nil") then
        return false
    end
    if (type(issecretvalue) == "function") then
        local okSecret, isSec = pcall(issecretvalue, v)
        -- If pcall fails with "Secret values are only allowed during untainted execution",
        -- that failure itself is proof positive that v is a secret value!
        if (not okSecret or isSec == true) then
            return true
        end
    end
    local canaccess = rawget(_G, "canaccessvalue")
    if (type(canaccess) == "function") then
        local okAccess, canAcc = pcall(canaccess, v)
        if (not okAccess or canAcc == false) then
            return true
        end
    end
    return false
end
local isSecretValue = TT.isSecretValue

-- Safe equality test preventing secret boolean comparison errors
function TT.safeEquals(a, b)
    if (type(a) == "nil" or type(b) == "nil" or isSecretValue(a) or isSecretValue(b)) then
        return false
    end
    local ok, eq = pcall(function() return a == b end)
    return ok and eq == true
end
local safeEquals = TT.safeEquals

-- Safe UnitExists wrapper
function TT.safeUnitExists(unit)
    if (type(unit) == "nil" or isSecretValue(unit) or type(UnitExists) ~= "function") then
        return false
    end
    local ok, exists = pcall(UnitExists, unit)
    if (not ok or isSecretValue(exists)) then
        return false
    end
    return exists == true
end
local safeUnitExists = TT.safeUnitExists

-- Safe UnitIsPlayer wrapper
function TT.safeUnitIsPlayer(unit)
    if (type(unit) == "nil" or isSecretValue(unit) or type(UnitIsPlayer) ~= "function") then
        return false
    end
    local ok, isP = pcall(UnitIsPlayer, unit)
    if (not ok or isSecretValue(isP)) then
        return false
    end
    return isP == true
end
local safeUnitIsPlayer = TT.safeUnitIsPlayer

-- Safe UnitIsUnit wrapper (protects against SecretWhenUnitComparisonRestricted)
function TT.safeUnitIsUnit(u1, u2)
    if (type(u1) == "nil" or type(u2) == "nil" or isSecretValue(u1) or isSecretValue(u2) or type(UnitIsUnit) ~= "function") then
        return false
    end
    local ok, isU = pcall(UnitIsUnit, u1, u2)
    if (not ok or isSecretValue(isU)) then
        return false
    end
    return isU == true
end
local safeUnitIsUnit = TT.safeUnitIsUnit

-- Safe UnitInParty wrapper
function TT.safeUnitInParty(unit)
    if (type(unit) == "nil" or isSecretValue(unit) or type(UnitInParty) ~= "function") then
        return false
    end
    local ok, inP = pcall(UnitInParty, unit)
    if (not ok or isSecretValue(inP)) then
        return false
    end
    return inP == true
end
local safeUnitInParty = TT.safeUnitInParty

-- Safe UnitInRaid wrapper (protects against SecretWhenUnitIdentityRestricted)
function TT.safeUnitInRaid(unit)
    if (type(unit) == "nil" or isSecretValue(unit) or type(UnitInRaid) ~= "function") then
        return false
    end
    local ok, inR = pcall(UnitInRaid, unit)
    if (not ok or isSecretValue(inR)) then
        return false
    end
    return type(inR) == "number" or inR == true
end
local safeUnitInRaid = TT.safeUnitInRaid

-- Safe UnitIsPVP wrapper (protects against SecretWhenUnitIdentityRestricted)
function TT.safeUnitIsPVP(unit)
    if (type(unit) == "nil" or isSecretValue(unit) or type(UnitIsPVP) ~= "function") then
        return false
    end
    local ok, isPVP = pcall(UnitIsPVP, unit)
    if (not ok or isSecretValue(isPVP)) then
        return false
    end
    return isPVP == true
end
local safeUnitIsPVP = TT.safeUnitIsPVP

```
