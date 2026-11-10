-- The custom_pos writer's 4-element contract, and the consumer that spends it.
--
-- WHY THIS FILE EXISTS. The options toggle wrote a FIVE-element table:
--
--   options.lua:4146 (HEAD a4cb20c)
--     TacoTipConfig.custom_pos = { "BOTTOMRIGHT", "UIParent", "BOTTOMRIGHT", -CONTAINER_OFFSET_X - 13, CONTAINER_OFFSET_Y }
--
-- The consumer treats the table as (point, relPoint, xOfs, yOfs):
--
--   main.lua:4364-4369  syncTooltipMoverPosition
--     local point    = tostring(pos[1] or "BOTTOMRIGHT")
--     local relPoint = tostring(pos[2] or "BOTTOMRIGHT")
--     local xOfs     = tonumber(pos[3]) or 0
--     local yOfs     = tonumber(pos[4]) or 0
--     TacoTipDragButton:SetPoint(point, UIParent, relPoint, xOfs, yOfs)
--   main.lua:6361-6368  the mover button's first placement (same mapping, with
--     a type-only fallback that a frame NAME still passes)
--
-- "UIParent" is a frame NAME, not an anchor point. It landed in the relPoint
-- slot, so the client's SetPoint raised "Unknown anchor type" and the frame was
-- never placed; the fourth and fifth values were then read from the wrong
-- positions. Both strings are type()-valid, which is why the mover fallback
-- (type(pos[2]) ~= "string") and the diagnostics validator
-- (main.lua:4921 checks p[1], p[3], p[4] -- NOT p[2]) both blessed it.
--
-- THE PIN. Read the real options.lua, extract the writer literal, evaluate it
-- with the harness's CONTAINER_OFFSET values (every harness models the client's
-- container offset as 0 -- see options_test.lua:358-359,
-- tooltip_test.lua:610, forever_tooltip_test.lua:462 and siblings), then assert
-- the shape the consumers read and hand it to a SetPoint mock that rejects
-- exactly what the client rejects: anything that is not an anchor point, and
-- non-numeric offsets.
--
-- Env override (red/green proof only; never used in gates):
--   TACOTIP_OPTIONS_OVERRIDE=/tmp/options_old.lua   a throwaway pre-fix copy
-- The pin was shown RED on a `git show HEAD:options.lua` copy and GREEN on the
-- working tree; see the header of secretguard_test.lua for the sibling pin.
--
-- Usage: lua5.1 Tests/harness/custompos_test.lua
-- Client-independent: the writer literal is not family-gated.

local _hp = ((arg and arg[0]) or "Tests/harness/custompos_test.lua"):gsub("\\", "/")
local _hd = _hp:match("^(.*)/[^/]*$") or "."
local ROOT = dofile(_hd .. "/root.lua") .. "/"

local unpack = unpack or table.unpack

local STD = {
    os = os, string = string, pairs = pairs, ipairs = ipairs, type = type,
    pcall = pcall, tonumber = tonumber, tostring = tostring, select = select,
    rawget = rawget, rawset = rawset, setmetatable = setmetatable,
    getmetatable = getmetatable, unpack = unpack, assert = assert, error = error,
    next = next, math = math, table = table, print = print, io = io,
    load = load, loadstring = loadstring, setfenv = setfenv,
}

local checks = {}
local function check(name, cond, detail)
    checks[#checks + 1] = { name, cond and true or false, detail }
end

local OPTIONS_PATH = STD.os.getenv("TACOTIP_OPTIONS_OVERRIDE") or (ROOT .. "options.lua")

local function readFile(path)
    local fh = assert(STD.io.open(path, "rb"), "cannot open " .. path)
    local src = fh:read("*a")
    fh:close()
    return src
end

-- The anchor points the client's SetPoint accepts. A frame NAME ("UIParent",
-- "TacoTipOptions", ...) is not one of them; that is the whole defect.
local ANCHORS = {
    TOPLEFT = true, TOP = true, TOPRIGHT = true,
    LEFT = true, CENTER = true, RIGHT = true,
    BOTTOMLEFT = true, BOTTOM = true, BOTTOMRIGHT = true,
}

-- Find the writer literal: the one line that assigns custom_pos a table starting
-- with a "BOTTOMRIGHT" string. Matched by shape rather than by line number so the
-- pin survives unrelated edits above it -- but a REFORMATTED writer must fail
-- loudly instead of silently pinning nothing, hence the exactly-one assertion.
local function findWriterLiterals(src)
    local found = {}
    for line in STD.string.gmatch(src, "[^\n]*") do
        if (STD.string.find(line, "TacoTipConfig.custom_pos", 1, true)
                and STD.string.find(line, '{ "BOTTOMRIGHT"', 1, true)) then
            local literal = STD.string.match(line, "(%b{})")
            if (literal) then
                found[#found + 1] = { literal = literal, line = line }
            end
        end
    end
    return found
end

-- Evaluate the extracted table constructor with the mocked client's container
-- offsets, exactly as the addon's closure evaluates it when the toggle fires.
local function evalWriterLiteral(literal)
    local env = { CONTAINER_OFFSET_X = 0, CONTAINER_OFFSET_Y = 0 }
    env._G = env
    local src = "return " .. literal
    local chunk
    if (STD.setfenv and STD.loadstring) then
        chunk = assert(STD.loadstring(src, "=custom_pos_writer"))
        STD.setfenv(chunk, env)
    else
        chunk = assert(STD.load(src, "=custom_pos_writer", "t", env))
    end
    return chunk()
end

-- The client's SetPoint. An unknown anchor type and a non-numeric offset are
-- errors in the client; mirroring them is what makes a frame name in the
-- relPoint slot observable here instead of silently accepted.
local UIParent = { __frame = "UIParent" }
local function makeSetPointSink()
    local calls = {}
    local function SetPoint(self, point, relativeTo, relPoint, xOfs, yOfs)
        if (not ANCHORS[point]) then
            STD.error("SetPoint: Unknown anchor type: " .. STD.tostring(point), 0)
        end
        if (not ANCHORS[relPoint]) then
            STD.error("SetPoint: Unknown anchor type: " .. STD.tostring(relPoint), 0)
        end
        if (relativeTo ~= UIParent) then
            STD.error("SetPoint: relativeTo is not UIParent", 0)
        end
        if (STD.type(xOfs) ~= "number" or STD.type(yOfs) ~= "number") then
            STD.error("SetPoint: offsets must be numbers", 0)
        end
        calls[#calls + 1] = { point = point, relPoint = relPoint, xOfs = xOfs, yOfs = yOfs }
    end
    return SetPoint, calls
end

-- main.lua:4364-4369, verbatim mapping (no fallback).
local function placeViaSync(SetPoint, pos)
    local point = STD.tostring(pos[1] or "BOTTOMRIGHT")
    local relPoint = STD.tostring(pos[2] or "BOTTOMRIGHT")
    local xOfs = STD.tonumber(pos[3]) or 0
    local yOfs = STD.tonumber(pos[4]) or 0
    return SetPoint(nil, point, UIParent, relPoint, xOfs, yOfs)
end

-- main.lua:6357-6368, the mover button's first placement: it falls back only on
-- a non-string, so a frame NAME survives the fallback and reaches SetPoint.
local function placeViaMover(SetPoint, pos)
    local fallback = { "BOTTOMRIGHT", "BOTTOMRIGHT", 0, 0 }
    if (STD.type(pos[1]) ~= "string" or STD.type(pos[2]) ~= "string") then
        pos = fallback
    end
    local point = STD.tostring(pos[1] or "BOTTOMRIGHT")
    local relPoint = STD.tostring(pos[2] or "BOTTOMRIGHT")
    local xOfs = STD.tonumber(pos[3]) or 0
    local yOfs = STD.tonumber(pos[4]) or 0
    return SetPoint(nil, point, UIParent, relPoint, xOfs, yOfs)
end

-- ---- the pin --------------------------------------------------------------

local src = readFile(OPTIONS_PATH)
local writers = findWriterLiterals(src)
check("options.lua carries exactly one custom_pos writer literal", #writers == 1,
    "found " .. STD.tostring(#writers) .. " in " .. OPTIONS_PATH)

local pos
if (#writers == 1) then
    local ok, value = STD.pcall(evalWriterLiteral, writers[1].literal)
    check("the custom_pos writer literal evaluates", ok and STD.type(value) == "table",
        "ok=" .. STD.tostring(ok) .. " err=" .. STD.tostring(value))
    if (ok and STD.type(value) == "table") then pos = value end
end

if (pos) then
    -- 1. The contract's arity. The consumer reads four slots; a fifth value is
    --    a slot the writer thinks exists and no consumer reads, which is exactly
    --    how a frame name ended up in pos[2].
    check("custom_pos has exactly 4 elements", #pos == 4,
        "#pos=" .. STD.tostring(#pos) .. " literal=" .. writers[1].literal)

    -- 2. pos[1] is the point, pos[2] is the relPoint: both must be anchor points.
    check("custom_pos[1] is a valid anchor point",
        STD.type(pos[1]) == "string" and ANCHORS[pos[1]] == true,
        "pos[1]=" .. STD.tostring(pos[1]))
    check("custom_pos[2] is a valid anchor point (relPoint, never a frame name)",
        STD.type(pos[2]) == "string" and ANCHORS[pos[2]] == true,
        "pos[2]=" .. STD.tostring(pos[2]))
    check("custom_pos[3] and custom_pos[4] are numeric offsets",
        STD.type(pos[3]) == "number" and STD.type(pos[4]) == "number",
        "pos[3]=" .. STD.tostring(pos[3]) .. " pos[4]=" .. STD.tostring(pos[4]))

    -- 3. Both real consumers must be able to place with it.
    local syncSetPoint, syncCalls = makeSetPointSink()
    local okSync, syncErr = STD.pcall(placeViaSync, syncSetPoint, pos)
    check("the syncTooltipMoverPosition consumer can SetPoint with it", okSync,
        STD.tostring(syncErr))

    local moverSetPoint, moverCalls = makeSetPointSink()
    local okMover, moverErr = STD.pcall(placeViaMover, moverSetPoint, pos)
    check("the mover-button consumer can SetPoint with it", okMover,
        STD.tostring(moverErr))

    -- 4. And it places the intended anchor, not the fallback: offsets are the
    --    writer's own -CONTAINER_OFFSET_X - 13 and CONTAINER_OFFSET_Y.
    check("the placed anchor is BOTTOMRIGHT/BOTTOMRIGHT on UIParent",
        #syncCalls == 1 and syncCalls[1].point == "BOTTOMRIGHT"
            and syncCalls[1].relPoint == "BOTTOMRIGHT",
        #syncCalls == 0 and "never placed"
            or ("point=" .. STD.tostring(syncCalls[1].point)
                .. " relPoint=" .. STD.tostring(syncCalls[1].relPoint)))
    check("the placed offsets are the writer's own (-13 from CONTAINER_OFFSET_X=0, 0)",
        #syncCalls == 1 and syncCalls[1].xOfs == -13 and syncCalls[1].yOfs == 0,
        #syncCalls == 0 and "never placed"
            or ("x=" .. STD.tostring(syncCalls[1].xOfs) .. " y=" .. STD.tostring(syncCalls[1].yOfs)))

    -- 5. The same value through the mover fallback: type()-validity is not
    --    anchor validity, so this path must accept it too -- and only because
    --    pos[2] really is an anchor, never because the fallback rescued it.
    check("the mover fallback was not needed (the writer is valid on its own)",
        #moverCalls == 1 and moverCalls[1].relPoint == "BOTTOMRIGHT"
            and moverCalls[1].xOfs == -13,
        #moverCalls == 0 and "never placed"
            or ("relPoint=" .. STD.tostring(moverCalls[1].relPoint)
                .. " x=" .. STD.tostring(moverCalls[1].xOfs)))
end

-- 6. The pin's own premise: the consumer maps pos[2] to relPoint. If that shape
--    ever changes, the emulation above must be re-derived, not silently kept.
do
    local mainSrc = readFile(ROOT .. "main.lua")
    local relPointMap = STD.string.match(mainSrc, "relPoint%s*=%s*tostring%(pos%[2%]")
    check("main.lua still maps pos[2] to relPoint (the pin's consumer premise)",
        relPointMap ~= nil, "pattern 'relPoint = tostring(pos[2]' not found in main.lua")
end

-- ---- report ---------------------------------------------------------------

STD.io.write("custom_pos writer: " .. OPTIONS_PATH .. "\n")

local fails = 0
for _, c in STD.ipairs(checks) do
    if (not c[2]) then
        fails = fails + 1
        STD.io.write(STD.string.format("    FAIL %-60s %s\n", c[1], STD.tostring(c[3] or "")))
    end
end
STD.io.write(STD.string.format("%-13s %s\n", "custompos",
    (fails == 0) and ("ALL " .. #checks .. " PASS") or (fails .. "/" .. #checks .. " FAILED")))
STD.os.exit(fails == 0 and 0 or 1)
