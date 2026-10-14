-- Resolves the addon root for the offline harness.
--
-- WHY THIS EXISTS. Every harness used to pin the absolute path
-- "/home/sam/TacoTip-Gearscore-TBC/TacoTip_Forever/" as a string literal. That
-- is invisible while you work on one machine and one checkout, and catastrophic
-- everywhere else: a copy, a worktree, a CI runner or a second machine runs the
-- harness and it loads the ORIGINAL files at that literal path, grading a tree
-- that is not the tree under test.
--
-- Proven, not theorised: relocating the addon, corrupting every Lua file in the
-- copy, and running the copy's own harness reported "50 passed, 1 failed" --
-- 50 of 51 invocations green with every production file a syntax error, because
-- they all read the untouched original. Only textures_test.lua failed, because
-- it was the only harness deriving its own location.
--
-- So the derivation lives here, once, and every harness dofiles it.

local scriptPath = ((arg and arg[0]) or "Tests/harness/root.lua"):gsub("\\", "/")
local harnessDir = scriptPath:match("^(.*)/[^/]*$") or "."
local root = harnessDir:gsub("Tests/harness/?$", ""):gsub("/+$", "")
if root == "" then root = "." end

-- Fail loudly. The whole failure mode this file exists to prevent is a harness
-- that silently grades a neighbouring tree, so a root without textures.lua in
-- it is an error, never a fallback to a default.
local probe = root .. "/textures.lua"
local fh = io.open(probe, "r")
if not fh then
    error("TacoTip harness: no textures.lua at '" .. probe
        .. "' -- root derived from arg[0]=" .. tostring(arg and arg[0])
        .. ". Run the suite from the addon directory, or fix the invocation.", 0)
end
fh:close()

return root