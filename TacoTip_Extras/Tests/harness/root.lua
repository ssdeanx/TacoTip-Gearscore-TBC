-- Resolves the TacoTip_Extras addon root for the offline harness.
--
-- WHY THIS EXISTS (borrowed verbatim in intent from TacoTip's own
-- Tests/harness/root.lua, which has the scar to prove it is needed).
--
-- Every harness that pins an absolute path as a string literal grades a tree
-- that is not the tree under test: a copy, a worktree or a CI runner loads the
-- ORIGINAL files at that literal path. TacoTip proved this the hard way --
-- relocating the addon, corrupting every Lua file in the copy, and running the
-- copy's own harness still reported "50 passed, 1 failed", because every file
-- it loaded came from the untouched original.
--
-- So the derivation lives here, once, and every harness dofiles it. Never
-- hardcode "/home/sam/TacoTip-Gearscore-TBC/TacoTip_Extras/" in a harness.

local scriptPath = ((arg and arg[0]) or "Tests/harness/root.lua"):gsub("\\", "/")
local harnessDir = scriptPath:match("^(.*)/[^/]*$") or "."
local root = harnessDir:gsub("Tests/harness/?$", ""):gsub("/+$", "")
if root == "" then root = "." end

-- Fail loudly. The whole failure mode this file exists to prevent is a harness
-- that silently grades a neighbouring tree, so a root without the TOC in it is
-- an error, never a fallback to a default.
--
-- The probe is the TOC, not a Lua file: the TOC is the one file whose name is
-- load-bearing (WoW refuses an add-on whose TOC name does not match its
-- folder), so if it is missing we are pointed at the wrong directory.
local probe = root .. "/TacoTip_Extras.toc"
local fh = io.open(probe, "r")
if not fh then
    error("TacoTip_Extras harness: no TacoTip_Extras.toc at '" .. probe
        .. "' -- root derived from arg[0]=" .. tostring(arg and arg[0])
        .. ". Run the suite from the addon directory, or fix the invocation.", 0)
end
fh:close()

return root