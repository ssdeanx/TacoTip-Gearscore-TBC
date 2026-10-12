# Blizzard FrameXML API Compatibility & Research Protocols

## 1. FrameXML Source Mapping

All WoW API research must reference the local Blizzard FrameXML repository at `/home/sam/wow-ui-source`:

| Target Client Flavor | Branch in `/home/sam/wow-ui-source` | Primary Focus |
| :--- | :--- | :--- |
| **Classic Era / SoD** | `origin/classic_era` (Interface `11509`) | Deprecation fallbacks, `GetGuildInfo` restrictions on patch 1.15.x, difficulty colors |
| **TBC Classic Anniversary** | `origin/classic_anniversary` (Interface `20506`) | `C_SpecializationInfo` query structs, `GetActiveSpecGroup`, backdrop mixins |
| **Titanforge Wrath** | `origin/classic_era` (Interface `38001`) | Achievement points, Wrath talent trees, glyphs |

---

## 2. Specialization & Talent Query Architecture

Modern Classic clients (TBC Anniversary 2.5.6 and Era/SoD 1.15.9) have moved towards `C_SpecializationInfo`:

- **Query Struct:**

  ```lua
  C_SpecializationInfo.GetTalentInfo({
      specializationIndex = tab,
      talentIndex = index,
      isInspect = isInspect,
      isPet = false,
      groupIndex = group
  })
  ```

- **Fallback Pattern:**
  `LibClassicInspector` implements a wrapper around `GetTalentInfo` that transparently builds the `C_SpecializationInfo.GetTalentInfo` query struct when top-level `_G.GetTalentInfo` deprecation fallbacks are disabled.

- **Nil Safety:** Always guard `select(5, GetTalentInfo(...))` with `or 0` to prevent nil arithmetic errors on sparse talent builds.

---

## 3. Strict Retail Isolation

Retail-only APIs (e.g. `C_Traits`, modern WidgetManager anchors) must NEVER bleed into Classic execution paths. Live/Retail feature additions require strict `WOW_PROJECT_ID == WOW_PROJECT_MAINLINE` gating.

---

## 4. Modern & Retail Compatibility in TacoTip_Extras

- **Tooltip Unit Resolution:**
  - Modern tooltip pipeline utilizes `TooltipUtil.GetDisplayedUnit(tooltip)` and `TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, ...)`.
  - Classic `tooltip:GetUnit()` returns `name, unit` (Classic) and `name, unit, guid` (Modern). Guard with `pcall` and check all return values before falling back to `UnitGUID` lookup against `mouseover`, `target`, `player`, and `focus`.
- **Character Frame Model Parenting:**
  - On Retail and WoW Forever, `CharacterModelFrame` is superseded by `CharacterModelScene`. When `CharacterModelFrame` is nil, adapter parenting and leased text validation fallback cleanly to `CharacterModelScene` and `PaperDollFrame`.
- **Flexible Modern Item Link Parsing:**
  - `Scoring.ParseEquippedLink` supports modern variable-length item links containing bonus IDs, modifiers, and crafting data (`#fields < 6` reject threshold instead of fixed `#fields ~= 20`).
- **Slot Divisors for Average Item Level:**
  - Classic Era, TBC, Titanforge, and Forever retain the ranged slot (slot 18), using 17 slots.
  - Retail (`interface >= 100000`) removed the ranged slot, using 16 slots.
- **Detailed Mode Default:**
  - Both tooltip mode and equipment display summaries default to **Detailed** across all supported client platforms.

---

## 5. Remote Inspection & `INVENTORY_READY` Callback Protocol

- **`INVENTORY_READY` Signature Parity:**
  - `LibClassicInspector` fires `("INVENTORY_READY", guid, true, unit)`.
  - `LibForeverInspector` fires `("INVENTORY_READY", guid, true, unit)` and `("TALENTS_READY", guid, unit)`.
  - Consumers (e.g. `TacoTip_Extras/Scanner.lua`) must defensively allow `isInspect` to be either `true` or `nil` (`isInspect ~= nil and isInspect ~= true` rejection) in case an alternative or legacy inspector publisher fires only `guid`.
- **Remote Unit Token Resolution:**
  - When inspecting a player via right-click contextual menus (guild roster, chat, `/who`, or friends list), the inspected player is frequently neither `"target"`, `"focus"`, nor `"mouseover"`.
  - `InspectFrame.unit` is the authoritative unit token provided by Blizzard's `InspectFrame`.
  - Both `LibForeverInspector:PlayerGUIDToUnitToken(guid)` and `Scanner.resolveRemoteUnit(guid, callbackUnit)` check `InspectFrame.unit` and verify `UnitGUID(InspectFrame.unit) == guid` before falling back to party/raid iterations.
- **Uncached Item ID Resolution on Remote Inspect:**
  - On remote units, `GetInventoryItemID(unit, slotID)` may return `nil` while `GetInventoryItemLink(unit, slotID)` returns a valid item string link.
  - `Scanner.captureSlot` extracts the numerical ID directly from the native link (`item:(%d+)`) when `rawItemID` is nil, preventing false `"inventory-id-link-contradiction"` parse aborts.
