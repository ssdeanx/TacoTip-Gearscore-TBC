# WoW Classic / TBC FrameXML and XML Reference

Use this file when the task involves Blizzard templates, XML-defined UI,
FrameXML source inspection, or deciding whether to build something in XML or Lua.

## ASCII Lua-vs-XML decision map

```ascii
Need static template tree reused across many widgets?
  |
  +-- YES --> XML/template path may help
  |
  +-- NO  --> prefer Lua CreateFrame path

Need highly dynamic/generated rows?
  |
  +-- YES --> prefer Lua CreateFrame path
```

## Core references (local Blizzard mirror)

All references below live inside `/home/sam/wow-ui-source/` (use the
`classic_anniversary` branch for this project):

- XML schema: `reference/ARCHITECTURE.md` + the `.xsd` under `Interface/AddOns/Blizzard_FrameXML/`
- FrameXML overview: `Interface/AddOns/Blizzard_FrameXML/` (read the addon source directly)
- Widget API: widget templates under `Interface/AddOns/Blizzard_FrameXML/`
- Widget handlers: widget templates under `Interface/AddOns/Blizzard_FrameXML/`
- Blizzard UI source: `/home/sam/wow-ui-source/` (the local mirror itself — no web fallback)

## Practical rule

Most addon UI can be built entirely in Lua with `CreateFrame()`.
XML is optional, not required.

Lua is usually better when:

- the layout is dynamic
- rows are generated from data
- you want easier conditional creation
- the project already uses Lua-first UI construction

XML can still help when:

- you want reusable template inheritance
- you want a static frame tree declared upfront
- you are mimicking Blizzard template-driven UI patterns

## XML root reminder

The local Blizzard FrameXML source shows the root `Ui` element and schema usage.
The exact namespace boilerplate matters when authoring XML files.

Skeleton:

```xml
<Ui xmlns="http://www.blizzard.com/wow/ui/"
    xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
    xsi:schemaLocation="http://www.blizzard.com/wow/ui/ ..\FrameXML\UI.xsd">
</Ui>
```

## Common XML elements

The schema and widget docs cover these frequently used elements:

- `<Frame>`
- `<Button>`
- `<CheckButton>`
- `<EditBox>`
- `<ScrollFrame>`
- `<Slider>`
- `<StatusBar>`
- `<Texture>`
- `<FontString>`
- `<Layers>` / `<Layer>`
- `<Anchors>` / `<Anchor>`
- `<Scripts>`

## Layer example

The widget templates under `Blizzard_FrameXML` document the standard draw order and XML layer usage.

Example:

```xml
<Frame>
    <Layers>
        <Layer level="ARTWORK">
            <Texture />
        </Layer>
    </Layers>
</Frame>
```

## Lua-vs-XML translation mindset

Many XML patterns map directly to Lua:

- `<Frame>` -> `CreateFrame("Frame", ...)`
- `<Texture>` -> `frame:CreateTexture(...)`
- `<FontString>` -> `frame:CreateFontString(...)`
- `<Scripts>` -> `frame:SetScript(...)`
- `<Anchor>` -> `frame:SetPoint(...)`

ASCII translation:

```ascii
XML declaration
  |
  v
Runtime widget tree
  |
  v
Equivalent CreateFrame/region calls
```

When debugging a Blizzard UI example, translate the template structure into Lua
only after understanding the inherited regions and scripts.

## Template-driven work

`CreateFrame()` can inherit templates, and template `OnLoad` scripts run.

That means template use is powerful, but it also means:

- you must know what the template already creates
- you must avoid duplicating built-in regions by accident
- you should inspect Blizzard source before assuming a template's structure

ASCII template caution:

```ascii
Template inherited
  |
  v
Hidden prebuilt regions/scripts may exist
  |
  v
Inspect before adding duplicate regions
```

## Source locations worth checking

These paths are especially useful for addon UI work:

- `Interface/AddOns/Blizzard_APIDocumentation`
- `Interface/AddOns/Blizzard_APIDocumentationGenerated`
- `Interface/AddOns/Blizzard_SharedXML`
- `Interface/AddOns/Blizzard_FrameXMLBase`
- `Interface/AddOns/Blizzard_UIPanels_Game`
- `Interface/AddOns/Blizzard_Settings_Shared`

Good examples:

- `Blizzard_SharedXML/Mainline/UIDropDownMenu.lua`
- `Blizzard_FrameXMLBase/GradualAnimatedStatusBar.lua`
- `Blizzard_UIPanels_Game/Mainline/CastingBarFrame.lua`

## Practical Classic/TBC advice

- Prefer Lua-first custom panels for compatibility unless XML/templates clearly
  simplify the job.
- When using templates, verify they exist and behave the same on the intended
  Classic/TBC client.
- Use XML as a layout tool, not as a substitute for understanding the runtime
  widget tree.
- If you are copying a Blizzard pattern, inspect both the XML and the Lua that
  drives it.
