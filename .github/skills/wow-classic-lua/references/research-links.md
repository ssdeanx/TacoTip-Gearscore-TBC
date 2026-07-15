# WoW Classic / TBC Addon Research — Local Source

All API and widget research is done against the **local official Blizzard
FrameXML mirror** at `/home/sam/wow-ui-source/`. It is the extracted game
client, tracked across every client version via git branches. Do NOT use any external web mirrors — they are incomplete and outdated
for Classic/TBC work.

## How to look up an API or widget

The repo root is `/home/sam/wow-ui-source/`. Use `git` to read branch-specific
files (see `/home/sam/wow-ui-source/SKILL.md` for the full branch matrix and
file-to-responsibility index).

```bash
# List every client branch
git -C /home/sam/wow-ui-source branch -a

# Read a specific API doc file on a specific client branch
git -C /home/sam/wow-ui-source show classic_anniversary:Interface/AddOns/Blizzard_APIDocumentationGenerated/API_CreateFrame.lua

# Diff an API between Classic and Retail to find divergence
git -C /home/sam/wow-ui-source diff classic..live -- Interface/AddOns/Blizzard_CombatLog/

# Diff against PTR to preview upcoming changes
git -C /home/sam/wow-ui-source diff live..ptr -- Interface/AddOns/Blizzard_FrameXML/
```

## Where things live (branch-agnostic paths)

- **API documentation (hand-written):** `Interface/AddOns/Blizzard_APIDocumentation/`
- **API documentation (auto-generated, 592 files):** `Interface/AddOns/Blizzard_APIDocumentationGenerated/`
- **Core widget/frame templates:** `Interface/AddOns/Blizzard_FrameXML/` (SecureTemplates, toasts, tooltips, alerts, color picker, cinematics)
- **Shared framework (ScrollBox, mixins, EventRegistry):** `Interface/AddOns/Blizzard_SharedXML/`
- **Root event hub / globals:** `Interface/AddOns/Blizzard_UIParent/`
- **Reference docs:** `reference/FILE_RESPONSIBILITY.md`, `reference/API_NAMESPACES.md`, `reference/VERSION_BRANCHES.md`, `reference/ARCHITECTURE.md`

## Common lookup patterns

| Need | Command |
| ------ | --------- |
| API signature / returns | `git -C /home/sam/wow-ui-source show <branch>:Interface/AddOns/Blizzard_APIDocumentationGenerated/API_<Name>.lua` |
| Widget / handler behavior | read the widget template under `Interface/AddOns/Blizzard_FrameXML/` |
| XML / template behavior | read the `.xml` under the relevant `Blizzard_*` addon + `reference/ARCHITECTURE.md` |
| Classic-vs-Retail diff | `git -C /home/sam/wow-ui-source diff classic..live -- Interface/AddOns/<Addon>/` |
| Upcoming PTR change | `git -C /home/sam/wow-ui-source diff live..ptr -- Interface/AddOns/<Addon>/` |

## Which branch for this project

SuperSwingTimer targets **TBC Anniversary (2.5.x)** primarily, with Classic Era
(1.15.x) support. Use:

- `classic_anniversary` — TBC Anniversary realms (primary target)
- `classic_era` — Classic Era / Season of Discovery
- `classic` — base Classic (Vanilla) for comparison
- `live` — Retail, only for divergence checks
