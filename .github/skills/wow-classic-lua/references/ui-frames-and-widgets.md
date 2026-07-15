# WoW Classic / TBC UI Frames and Widgets Reference

Use this file when the task involves `CreateFrame`, status bars, config panels,
dragging, textures, font strings, sliders, scroll frames, or dropdown UI.

## ASCII widget build pipeline

```ascii
+------------------------------+
| CreateFrame                  |
+------------------------------+
| base frame settings          |
| regions (texture/font/status)|
| scripts (event/update/mouse) |
| style/layer pass             |
+------------------------------+
              |
              v
+------------------------------+
| Runtime visibility/updates   |
+------------------------------+
```

## Core entry point: `CreateFrame`

Local source: /home/sam/wow-ui-source — Blizzard_FrameXML CreateFrame template (branch: classic_anniversary)

Signature:

```lua
CreateFrame(frameType[, name, parent, template, id])
```

Key notes:

- `frameType` chooses the widget class.
- `name` is optional; use it only when you need a named global frame.
- `parent` is usually `UIParent` or another frame you own.
- `template` may be a comma-delimited template list on TBC-era clients and
  later.
- `OnLoad` from inherited templates runs automatically.
- Frames are not normally destroyed, so prefer reuse over repeated recreation.

Common frame types:

- `Frame`
- `Button`
- `CheckButton`
- `EditBox`
- `ScrollFrame`
- `Slider`
- `StatusBar`
- `GameTooltip`

## Minimal frame pattern

```lua
local frame = CreateFrame("Frame", "MyAddonFrame", UIParent)
frame:SetPoint("CENTER")
frame:SetSize(200, 40)
frame:RegisterEvent("PLAYER_LOGIN")

frame:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_LOGIN" then
        -- initialize addon UI here
    end
end)
```

## Frame methods worth remembering

Local source: /home/sam/wow-ui-source — Blizzard_FrameXML Frame widget (branch: classic_anniversary)

Frequently used methods:

- `SetPoint`, `ClearAllPoints`, `SetSize`, `SetWidth`, `SetHeight`
- `Show`, `Hide`, `IsShown`
- `SetScript`, `HookScript`
- `RegisterEvent`, `UnregisterEvent`, `RegisterUnitEvent`
- `CreateTexture`, `CreateFontString`, `CreateMaskTexture`
- `EnableMouse`, `RegisterForDrag`, `SetMovable`, `StartMoving`, `StopMovingOrSizing`
- `SetFrameStrata`, `SetFrameLevel`

Common script handlers:

- `OnLoad`
- `OnShow`
- `OnHide`
- `OnEvent`
- `OnUpdate`
- `OnEnter`
- `OnLeave`
- `OnMouseDown`
- `OnMouseUp`
- `OnDragStart`
- `OnDragStop`
- `OnMouseWheel`

## `OnEvent` pattern

Local source: /home/sam/wow-ui-source — Blizzard_FrameXML OnEvent handler (branch: classic_anniversary)

```lua
frame:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_TARGET_CHANGED" then
        RefreshTargetState()
    elseif event == "UNIT_ATTACK_SPEED" then
        local unit = ...
        if unit == "player" then
            RefreshPlayerSpeed()
        end
    end
end)
```

## `OnUpdate` pattern

Local source: /home/sam/wow-ui-source — Blizzard_FrameXML OnUpdate handler (branch: classic_anniversary)

- Signature: `OnUpdate(self, elapsed)`
- It only runs while the frame and its parents are visible.
- It is expensive if abused.
- Throttle it when per-frame precision is not required.

Throttled pattern:

```lua
local accum = 0
frame:SetScript("OnUpdate", function(self, elapsed)
    accum = accum + elapsed
    if accum < 0.05 then
        return
    end

    accum = 0
    RefreshDisplay()
end)
```

## Status bars

Local source: /home/sam/wow-ui-source — Blizzard_FrameXML StatusBar widget (branch: classic_anniversary)

```lua
local bar = CreateFrame("StatusBar", nil, UIParent)
bar:SetPoint("CENTER")
bar:SetSize(220, 14)
bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
bar:SetStatusBarColor(1, 0, 0, 1)
bar:SetMinMaxValues(0, 1)
bar:SetValue(0.5)
```

Useful methods:

- `SetStatusBarTexture`
- `GetStatusBarTexture`
- `SetStatusBarColor`
- `SetMinMaxValues`
- `SetValue`
- `SetOrientation`
- `SetReverseFill`

Practical rule:

- Use `bar:GetStatusBarTexture():SetDrawLayer(...)` when you need explicit
  control over fill layering relative to sparks or overlays.

## Textures

Local source: /home/sam/wow-ui-source — Blizzard_FrameXML Texture region (branch: classic_anniversary)

```lua
local tex = frame:CreateTexture(nil, "OVERLAY")
tex:SetAllPoints()
tex:SetTexture("Interface\\Buttons\\WHITE8X8")
tex:SetVertexColor(1, 1, 1, 0.35)
```

Useful methods:

- `SetTexture`
- `SetColorTexture`
- `SetVertexColor`
- `SetBlendMode`
- `SetTexCoord`
- `SetRotation`
- `SetDrawLayer`

Use cases:

- `SetTexture` for actual texture assets or file IDs
- `SetColorTexture` for flat fills and simple blocks
- `SetVertexColor` for tinting an existing asset

## Font strings

Local source: /home/sam/wow-ui-source — Blizzard_FrameXML FontString region (branch: classic_anniversary)

```lua
local label = frame:CreateFontString(nil, "OVERLAY", "GameTooltipText")
label:SetPoint("CENTER")
label:SetText("Hello world")
```

Useful methods:

- `SetText`
- `SetFont`
- `SetFontObject`
- `SetTextColor`
- `SetShadowColor`
- `SetShadowOffset`
- `GetStringWidth`
- `GetStringHeight`

## Draw layers

Local sources (Blizzard_FrameXML, branch: classic_anniversary):

- Layer draw order: widget templates under `Blizzard_FrameXML/`
- Widget API: widget templates under `Blizzard_FrameXML/`

Layer order inside a frame:

1. `BACKGROUND`
2. `BORDER`
3. `ARTWORK`
4. `OVERLAY`
5. `HIGHLIGHT`

ASCII stacking model:

```ascii
back
 |
 +--> BACKGROUND
 +--> BORDER
 +--> ARTWORK
 +--> OVERLAY
 +--> HIGHLIGHT
 |
front
```

Notes:

- Regions in the same layer can use a numeric sublayer.
- The layer is within a frame; frame strata and frame level still matter across
  separate frames.
- Transparent overlaps can look different depending on order and blend mode.

## Scroll frames

Local source: /home/sam/wow-ui-source — Blizzard_FrameXML ScrollFrame widget (branch: classic_anniversary)

Useful methods:

- `SetScrollChild`
- `SetVerticalScroll`
- `GetVerticalScrollRange`
- `UpdateScrollChildRect`

Good fit for:

- long config panels
- texture browsers
- dynamic lists

See also: `Interface/AddOns/Blizzard_FrameXML/` scroll-frame templates in the local mirror

## Sliders

Local source: /home/sam/wow-ui-source — Blizzard_FrameXML Slider widget (branch: classic_anniversary)

```lua
local slider = CreateFrame("Slider", nil, UIParent, "UISliderTemplateWithLabels")
slider:SetMinMaxValues(0, 100)
slider:SetValue(50)
slider:SetValueStep(1)
slider:SetObeyStepOnDrag(true)
slider:SetScript("OnValueChanged", function(self, value)
    print(value)
end)
```

Useful methods:

- `SetMinMaxValues`
- `SetValue`
- `SetValueStep`
- `SetObeyStepOnDrag`
- `GetValue`
- `GetThumbTexture`

Relevant handlers:

- `OnMinMaxChanged`
- `OnValueChanged(self, value, userInput)`

## Dropdowns

Local sources (Blizzard_FrameXML, branch: classic_anniversary):

- `UIDropDownMenu_Initialize`: `Blizzard_FrameXML` dropdown templates
- `UIDropDownMenu_CreateInfo`: `Blizzard_FrameXML` dropdown templates

Classic pattern:

```lua
local dropdown = CreateFrame("Frame", "MyAddonDropdown", parent, "UIDropDownMenuTemplate")

UIDropDownMenu_Initialize(dropdown, function(self, level)
    local info = UIDropDownMenu_CreateInfo()
    info.text = "Option A"
    info.checked = currentValue == "a"
    info.func = function()
        currentValue = "a"
        UIDropDownMenu_SetText(dropdown, "Option A")
    end
    UIDropDownMenu_AddButton(info, level)
end)
```

Practical rules:

- Use `checked` on the info table for current selection.
- Use `menuList` and `hasArrow` only when a real submenu is needed.
- Keep long or visual-heavy selectors in a custom scrollable popup when the
  stock dropdown becomes awkward.

ASCII dropdown flow:

```ascii
Initialize dropdown
    |
    v
Build info rows
    |
    v
Mark checked row
    |
    v
Handle selection
    |
    v
Update label + saved value
```

## Buttons, check buttons, and edit boxes

Useful `Widget_script_handlers` source:

- widget templates under `Blizzard_FrameXML/` (branch: classic_anniversary)

Highlights:

- `Button` supports `OnClick`, `PreClick`, `PostClick`
- `CheckButton` still uses button-style click handling patterns
- `EditBox` supports `OnTextChanged`, `OnEnterPressed`, `OnEscapePressed`
- `StatusBar` and `Slider` use `OnValueChanged`

## Tooltips

- Use `GameTooltipTemplate` when creating a tooltip frame.
- For row help, wire `OnEnter` / `OnLeave` and anchor the tooltip explicitly.

Example:

```lua
local tooltip = CreateFrame("GameTooltip", "MyAddonTooltip", UIParent, "GameTooltipTemplate")

row:SetScript("OnEnter", function(self)
    tooltip:SetOwner(self, "ANCHOR_RIGHT")
    tooltip:SetText("Helpful addon text")
    tooltip:Show()
end)

row:SetScript("OnLeave", function()
    tooltip:Hide()
end)
```

## In-game UI debugging

- `/fstack` is the first tool to reach for when layering, hit rects, or parentage
  look wrong.
- If HIGHLIGHT behavior is involved, remember it is tied to mouse-enabled frames.
- If a region appears to vanish after skinning or texture refresh, re-check both
  draw layer and the order in which textures are recreated or restyled.
