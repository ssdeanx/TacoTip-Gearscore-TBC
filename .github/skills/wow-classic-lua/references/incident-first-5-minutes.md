# Incident First 5 Minutes (WoW Classic/TBC Addon)

Use this playbook the moment a bug report lands.

## ASCII first-5-min flow

```ascii
+-------------------------------+
| 0) Reproduce quickly          |
+-------------------------------+
              |
              v
+-------------------------------+
| 1) Classify failure           |
|    state vs render vs config  |
+-------------------------------+
              |
              v
+-------------------------------+
| 2) Identify event family      |
|    CLEU / SPELLCAST / UI      |
+-------------------------------+
              |
              v
+-------------------------------+
| 3) Is it combat-only?         |
|    yes -> taint/secure audit  |
+-------------------------------+
              |
              v
+-------------------------------+
| 4) Patch smallest owner file  |
+-------------------------------+
              |
              v
+-------------------------------+
| 5) Run targeted playbook      |
+-------------------------------+
```

## Minute-by-minute script

### Minute 0-1: capture report signal

Collect:

- class/spec
- where (zone/target context)
- expected vs actual
- whether combat-only
- whether `/reload` temporarily clears

### Minute 1-2: classify subsystem

- state wrong -> likely `State.lua` / `Weaving.lua`
- rendering wrong -> likely `UI.lua` / `ClassMods.lua`
- config-only wrong -> likely `Config.lua` / defaults/migration

### Minute 2-3: identify event path

Use `event-payload-cheatsheet.md` to map reported behavior to event family.

### Minute 3-4: select owner file + minimal patch

Patch only the owner file first.

### Minute 4-5: verify with the right playbook

Use `verification-playbooks.md` subsystem checks (hunter/shaman/swing/config/taint).

## Incident note template

- **Issue**:
- **Class/spec**:
- **Event family**:
- **Owner file patched**:
- **Patch summary (1-2 lines)**:
- **Verification playbook used**:
- **Result**:

## Escalation rule

If first patch fails, do not broaden blindly — re-check event family and
whether the bug is authoritative state vs rendering-only before second patch.
