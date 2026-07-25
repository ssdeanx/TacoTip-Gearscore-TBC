---
name: wow-api-auditor
description: Automates the process of researching official Blizzard FrameXML UI code to find precise API signatures and usage across different WoW clients (Classic Era, TBC/Wrath, Retail).
---

# WoW API Auditor Skill

Use this skill whenever you need to verify how a Blizzard API function works, what its signature is, or whether it behaves differently between Classic and Retail.

## Instructions

1. **Locate the Source Repo:** The official Blizzard FrameXML repository is cloned locally at `/home/sam/wow-ui-source`.
2. **Determine the Target Branch:**
   - **Vanilla / Classic Era / SoD:** `origin/classic_era`
   - **TBC Anniversary / Wrath:** `origin/classic`
   - **Live / Retail:** `origin/mainline`
3. **Execute the Search:**
   - Use the `run_command` tool to search for the API.
   - Example Command:
     ```bash
     cd /home/sam/wow-ui-source && git checkout <target_branch> && git grep -n "API_Name"
     ```
4. **Analyze the Results:**
   - Look for the function definition (usually in C-side declarations or Lua wrapper definitions) or how Blizzard's own UI code invokes it.
   - Note any parameter differences across branches (e.g., `GetGuildInfo` requires a unit token on Classic Era but not necessarily on older Vanilla clients).
5. **Apply Findings:** Use the exact signature found in your codebase modifications. Do not guess parameters based on web wikis, as they are often outdated.
