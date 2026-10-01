-- Verifies the ported static talent table (from the working LibClassicInspector) resolves
-- real icons per expansion, without loading the whole addon.
-- Usage: lua5.1 talent_check.lua <projectId> <iface> <label>
-- Verifies the ported static talent table resolves icons the same way the
-- working LibClassicInspector does, without loading the whole addon.
local D = (os.getenv("TACOTIP_TEST_ROOT") or ".") .. "/"
local PROJ = tonumber(arg[1]) or 2
local IFACE = tonumber(arg[2]) or 11509
local LABEL = arg[3] or "CLASSIC_ERA"
local REALG = _G
local out = print

REALG.CreateFrame = function()
    return {
        SetScript = function() end,
        RegisterEvent = function() end,
        UnregisterEvent = function() end,
        IsShown = function() return false end,
        RegisterUnitEvent = function() end,
    }
end
REALG.GetBuildInfo = function() return "1.15.9", "1", "d", IFACE, "us", "rel" end
REALG.WOW_PROJECT_MAINLINE = 1
REALG.WOW_PROJECT_CLASSIC = 2
REALG.WOW_PROJECT_BC_CLASSIC = 5
REALG.WOW_PROJECT_WRATH_CLASSIC = 11
REALG.WOW_PROJECT_ID = PROJ
REALG.UnitClass = function() return "WARRIOR", "WARRIOR" end
REALG.UnitExists = function() return true end
REALG.UnitIsPlayer = function() return true end
REALG.UnitGUID = function() return "Player-1-0" end
REALG.wipe = table.wipe

for _, f in ipairs({
    "Libs/LibStub/LibStub.lua",
    "Libs/CallbackHandler-1.0/CallbackHandler-1.0.lua",
    "Libs/LibDetours-1.0/LibDetours-1.0.lua",
    "Libs/LibForeverInspector/LibForeverInspector.lua",
}) do
    local ok, err = pcall(function() assert(loadfile(D .. f))("T") end)
    if not ok then
        out("LOAD FAIL " .. f .. ": " .. tostring(err))
        os.exit(1)
    end
end

local lib = LibStub("LibForeverInspector", true)
out("== " .. LABEL .. " (projectId=" .. PROJ .. ", iface=" .. IFACE .. ") family=" .. tostring(lib.family))
out("GetTalentInfoByClass= " .. type(lib.GetTalentInfoByClass))
out("GetNumTalentsByClass= " .. type(lib.GetNumTalentsByClass))

-- Spot-check a known record straight from the working table.
local probe = 26
while true do
    local n = lib.GetTalentInfoByClass(lib, "WARRIOR", 1, probe)
    if n or probe <= 1 then break end
    probe = probe - 1
end
local name, tex, tier, col, _, maxR, exc =
    lib.GetTalentInfoByClass(lib, "WARRIOR", 1, probe)
out(string.format("WARRIOR tab1 #%-2d     = %-18s tex=%s tier=%s col=%s maxR=%s exc=%s",
    probe, tostring(name), tostring(tex), tostring(tier), tostring(col), tostring(maxR), tostring(exc)))
out("numTalents WARRIOR 1 = " .. tostring(lib:GetNumTalentsByClass("WARRIOR", 1)))

-- Replay main.lua's getSpecializationIcon loop verbatim for a few classes.
for _, class in ipairs({ "WARRIOR", "MAGE", "ROGUE", "DRUID", "DEATHKNIGHT" }) do
    local best, bestTier = nil, -1
    for i = 1, 40 do
        local ok2, n2, tex2, ti2, _, _, _, exc2 =
            pcall(lib.GetTalentInfoByClass, lib, class, 1, i)
        if not ok2 then break end
        if n2 and tex2 then
            if exc2 then
                best, bestTier = tex2, math.huge
            elseif (ti2 or 0) >= bestTier then
                best, bestTier = tex2, ti2 or 0
            end
        end
    end
    out(string.format("icon %-12s tab1 = %s", class, tostring(best)))
end
