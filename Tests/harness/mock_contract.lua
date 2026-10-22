-- The mock-fidelity contract.
--
-- Every mock in this harness tree is a CLAIM about what the client does. The
-- proctor audit (bench/audits/2026-10-19-test-sufficiency-audit.md, M4-M6 and
-- HI-12) found three mocks that did not match the client, and every one of
-- them was invisible to the suite: the suite was green while the mock and the
-- client disagreed. The audit's own conclusion was that a contract test
-- ("{api, realArity, mockArity}", sourced from the mirror) would catch the
-- next drift mechanically instead of waiting for a human to read FrameXML.
--
-- This file is that table. ONE place records, per API:
--   realArity  -- how many values the CLIENT publishes
--   mockArity  -- how many values the mock is expected to publish
--   source     -- where in the mirror the client truth was read, branch-
--                 qualified (decision D13: an unqualified citation is not
--                 evidence)
--   owner      -- the harness file whose mock the entry describes
--
-- realArity and mockArity are normally the same number. They are separate
-- fields so a DELIBERATE deviation has to say so in `note` rather than hide
-- inside the assertion.
--
-- How to use it:
--   local M = dofile(<harness dir> .. "/mock_contract.lua")
--   M.setFamily("retail")                       -- the client this run models
--   M.assertArity(check, "UnitClass", REALG.UnitClass)
--
-- The check() the helper takes is the MAIN-suite order: check(name, cond,
-- detail). The Extras suite's check() is the other order, so that harness
-- passes a one-line adapter.
--
-- Reading the mirror: /home/sam/wow-ui-source, one branch per client family
-- (see Tests/harness/README.md for the branch table and the reading rules).
--
--   git -C /home/sam/wow-ui-source show origin/live:<path>
--   git -C /home/sam/wow-ui-source grep -n '<pattern>' origin/<branch> -- '<path>'
--
-- A universal claim ("returns N values on every branch") needs all five
-- branches checked. One branch is an anecdote.

local M = {}

-- The family this run models. The harnesses know their own client; they tell
-- the contract so the per-family arities resolve.
local family = nil

function M.setFamily(f)
    family = f
end

function M.family()
    return family
end

-- Normalise the family labels the harnesses use. The library's own names are
-- the canonical ones ("classicEra", "tbc", "titanforge", "forever", "retail");
-- the harnesses that take an upper-case label are mapped onto them.
local FAMILY_ALIASES = {
    CLASSIC_ERA = "classicEra", classicEra = "classicEra", classic_era = "classicEra", ERA = "classicEra",
    TBC_ANNIV = "tbc", tbc = "tbc", TBC = "tbc",
    TITANFORGE = "titanforge", titanforge = "titanforge",
    FOREVER = "forever", forever = "forever",
    RETAIL = "retail", retail = "retail",
    UNKNOWN = "unknown", unknown = "unknown",
}

function M.normaliseFamily(label)
    local f = FAMILY_ALIASES[label]
    if (f) then return f end
    return label
end

-- ---------------------------------------------------------------------------
-- THE TABLE.
--
-- realArity: number, or a per-family table when the client differs.
-- mockArity: number, or a per-family table. Normally equal to realArity.
-- ---------------------------------------------------------------------------
M.APIS = {
    -- UnitClass publishes THREE values on the modern pair and TWO on the
    -- Classic family. This is the mock the proctor flagged (M4): every
    -- harness modelled one shape for five clients.
    --
    --   origin/live, origin/forever:
    --     Interface/AddOns/Blizzard_SharedXML/UnitUtil.lua:81
    --       local classID = select(3, UnitClass("player"));
    --     Interface/AddOns/Blizzard_ClassMenu/Blizzard_ClassMenu.lua:7
    --       local name, tag, classID = UnitClass("player");
    --   origin/classic_era, origin/classic_anniversary, origin/classic_titan:
    --     Interface/AddOns/Blizzard_InspectUI/Vanilla/InspectPaperDollFrame.lua:10
    --       local classDisplayName, class = UnitClass(InspectFrame.unit);
    --
    -- The addon reads #1 and #2 only, so the third value is latent rather than
    -- live -- but a latent gap is exactly what the next reader mistakes for a
    -- fact.
    UnitClass = {
        owner = "every MAIN harness, plus both Extras harnesses",
        realArity = { classicEra = 2, tbc = 2, titanforge = 2, forever = 3, retail = 3 },
        mockArity = { classicEra = 2, tbc = 2, titanforge = 2, forever = 3, retail = 3 },
        source = "UnitUtil.lua:81 (live/forever) vs InspectPaperDollFrame.lua:10 (classic family)",
        probe = function() return { "player" } end,
    },

    -- GetSpecializationInfoByID publishes SEVEN values:
    --   id, name, description, texture, role, class, classDisplayName
    --
    --   origin/live:
    --     Interface/AddOns/Blizzard_Communities/ClubFinder.lua:599
    --       local id, name, description, texture, role, class, classDisplayName
    --           = GetSpecializationInfoByID(specId);
    --
    -- The proctor flagged the 4-value mock (M5). The addon reads #2 (name) and
    -- #4 (icon) only, so #5+ were latent gaps.
    GetSpecializationInfoByID = {
        owner = "tooltip_test, detect_test, fileguard_test, and the Extras rankbrowser_test",
        realArity = 7,
        mockArity = 7,
        source = "ClubFinder.lua:599 (live): seven values",
        -- A REAL spec id, so the probe takes the mock's "found" branch: a
        -- probe that missed would measure the not-found branch's arity and
        -- could not see a mock that only lost a value on the found branch.
        probe = function() return { 71 } end,
    },

    -- GameTooltip:GetUnit publishes TWO values (name, unit). Batch 7 removed
    -- the phantom third GUID; this entry keeps that from coming back.
    --
    --   origin/classic_era, origin/classic_anniversary, origin/classic_titan:
    --     Interface/AddOns/Blizzard_PTRFeedback/Blizzard_PTRFeedback_Tooltips.lua:87
    --       local name, unit = self:GetUnit();
    --   origin/forever, origin/live: the same file at :105
    --
    -- The GUID comes from the SIBLING resolver
    -- (Interface/AddOns/Blizzard_SharedXMLGame/Tooltip/TooltipUtil.lua:40),
    -- which does not exist on the Classic family.
    GetUnit = {
        owner = "tooltip_test",
        realArity = 2,
        mockArity = 2,
        source = "Blizzard_PTRFeedback_Tooltips.lua:87 (classic) / :105 (modern)",
        probe = function() return {} end,
    },

    -- FauxScrollFrame_Update publishes ONE value: showScrollBar, which is 1
    -- when there is more than one screen of items and nil otherwise.
    --
    --   origin/classic_era, origin/classic_anniversary, origin/classic_titan,
    --   origin/forever, origin/live:
    --     Interface/AddOns/Blizzard_SharedXML/SecureScrollTemplates.lua:158
    --       function FauxScrollFrame_Update(frame, numItems, numToDisplay, ...)
    --     ... :224
    --       return showScrollBar;
    --
    -- The proctor recorded this API as returning NOTHING (M6), citing
    -- "SecureScrollTemplates.lua:158-222". The function body ends at :224 with
    -- `return showScrollBar;` -- :222 is inside the body. The real arity is
    -- ONE, and the mock in the Extras harness already published exactly that
    -- (1 when there are more items than fit, nil otherwise), so it was
    -- corrected by the CONTRACT, not by the mock: changing the mock to the
    -- audited "no return" would have made it LESS faithful.
    FauxScrollFrame_Update = {
        owner = "TacoTip_Extras/Tests/harness/rankbrowser_test",
        realArity = 1,
        mockArity = 1,
        source = "SecureScrollTemplates.lua:224 (all five branches): return showScrollBar",
        probe = function() return { {}, 10, 5, 1 } end,
    },

    -- C_PaperDollInfo.GetInspectGuildInfo publishes FOUR values: achievement
    -- points, member count, guild name, realm name.
    --
    --   origin/live:
    --     Interface/AddOns/Blizzard_APIDocumentationGenerated/PaperDollInfoDocumentation.lua:95
    --       { Name = "achievementPoints", Type = "number", ... },
    --       { Name = "numMembers", Type = "number", ... },
    --       { Name = "guildName", Type = "string", ... },
    --       { Name = "realmName", Type = "string", ... },
    --   origin/forever: the same file at :104
    --
    -- The guild guard reads the FOURTH (the realm name). It is nil for a
    -- player with no guild, and that nil is what Blizzard's own
    -- InspectGuildFrame formats unguarded -- so the fourth value is the fact
    -- the guard uses to tell Blizzard's defect from any other error.
    GetInspectGuildInfo = {
        owner = "tooltip_test",
        realArity = 4,
        mockArity = 4,
        source = "PaperDollInfoDocumentation.lua:95 (live) / :104 (forever)",
        probe = function() return { "target" } end,
    },

    -- C_Item.GetItemNumSockets publishes ONE value: socketCount. It is the
    -- documented source of truth for an item's socket count.
    --
    --   origin/live:
    --     Interface/AddOns/Blizzard_APIDocumentationGenerated/ItemDocumentation.lua:854
    --       Name = "GetItemNumSockets", Type = "Function",
    --       Arguments = { { Name = "itemInfo", Type = "ItemInfo", Nilable = false } },
    --       Returns  = { { Name = "socketCount", Type = "number", Nilable = false } },
    --   origin/forever: the same file at :876
    --   origin/classic_era, origin/classic_anniversary, origin/classic_titan:
    --     the same file at :586
    --
    -- The generated docs name the argument "itemInfo" -- an opaque item
    -- handle -- and do not say how to build one from a link. Blizzard's own
    -- call site settles it: the RAW ITEM LINK is the argument.
    --
    --   origin/live:
    --     Interface/AddOns/Blizzard_UIPanels_Game/Mainline/PaperDollFrame.lua:1728
    --       self.SocketDisplay:SetItem(GetInventoryItemLink("player", self:GetID()));
    --     :2775
    --       local numSockets = C_Item.GetItemNumSockets(item);
    --
    -- It is documented on the CLASSIC branches too, which is why the mock
    -- installs it on every client: the add-on's socket path is gated on
    -- GetItemStats, and a model that simply lacked this API would make the
    -- Classic degradation look like an accident of the model instead of the
    -- gate's doing.
    ["C_Item.GetItemNumSockets"] = {
        owner = "TacoTip_Extras/Tests/harness/load_test.lua",
        realArity = 1,
        mockArity = 1,
        source = "ItemDocumentation.lua:854 (live) / :876 (forever) / :586 (classic family)",
        probe = function() return { "|cffffffff|Hitem:50003:0:41398:0:0|h[Item]|h|r" } end,
    },
}

-- ---------------------------------------------------------------------------
-- RULES: the mock facts that are not ARITIES.
--
-- The APIS table above answers "how many values does this function publish".
-- Some client facts are not about a return value at all but about WHICH
-- MEMBERS a frame carries, and those are the ones a permissive mock hides
-- most easily: a mock that answers every key with a function looks like a
-- client that has every method.
-- ---------------------------------------------------------------------------
M.RULES = {
    -- The backdrop API is TEMPLATE-DEPENDENT.
    --
    -- A plain CreateFrame("Frame", ...) has NO SetBackdrop /
    -- SetBackdropColor / SetBackdropBorderColor. Only a template that mixes in
    -- BackdropTemplateMixin carries them, and the only such template is
    -- BackdropTemplate itself:
    --
    --   origin/classic_era          Interface/AddOns/Blizzard_SharedXML/Backdrop.xml:5
    --   origin/classic_anniversary  Interface/AddOns/Blizzard_SharedXML/Backdrop.xml:5
    --   origin/classic_titan        Interface/AddOns/Blizzard_SharedXML/Backdrop.xml:5
    --   origin/forever              Interface/AddOns/Blizzard_SharedXML/Backdrop.xml:5
    --   origin/live                 Interface/AddOns/Blizzard_SharedXML/Backdrop.xml:5
    --       <Frame name="BackdropTemplate" mixin="BackdropTemplateMixin" virtual="true">
    --   and the mixin, on every one of them:
    --   Interface/AddOns/Blizzard_SharedXML/Backdrop.lua:336 / :406 / :429
    --       SetBackdrop / SetBackdropColor / SetBackdropBorderColor
    --
    -- The tooltip chain is NOT one of them: SharedTooltipTemplate /
    -- TooltipBackdropTemplate mix in TooltipBackdropTemplateMixin, and
    -- SharedTooltipArtTemplate's NineSlice child inherits
    -- NineSlicePanelTemplate -> NineSliceCodeTemplate
    -- (origin/live Interface/AddOns/Blizzard_SharedXML/Mainline/
    -- SharedUIPanelTemplates.xml:381), which mixes in nothing. So neither the
    -- tooltip nor its NineSlice has the backdrop API on any client.
    --
    -- WHY IT IS HERE. `if f.SetBackdrop then` is the CLIENT's own way of asking
    -- whether a frame has a backdrop, and a mock that always answers yes makes
    -- the guard unobservable. That is exactly how the Extras' gear panel
    -- shipped TRANSPARENT: the guard was skipped in the client and the harness
    -- could not see it. The MAIN harness's frame mock had the same divergence
    -- -- its generic no-op surface answered every key -- and is fixed by the
    -- same mechanism the Extras harness already uses (the `__absent` set,
    -- consulted first and through rawget).
    backdropTemplate = {
        owner = "Tests/harness/load_test.lua (the MAIN harness frame mock)",
        templates = { BackdropTemplate = true },
        api = { "SetBackdrop", "SetBackdropColor", "SetBackdropBorderColor" },
        source = "Backdrop.xml:5 (all five branches) + Backdrop.lua:336/:406/:429",
    },
}

-- Assert that a frame mock honours the backdrop-template rule.
--
-- createFrame is the mock's own CreateFrame, called the way the client calls
-- it: (kind, name, parent, template).
--
-- The check() the helper takes is the MAIN-suite order: check(name, cond,
-- detail).
--
-- Returns true when the mock honours the rule.
function M.assertBackdropTemplateRule(check, createFrame)
    local rule = M.RULES.backdropTemplate
    if (not rule) then
        check("mock contract knows the backdrop-template rule", false, "no contract entry")
        return false
    end
    local plain = createFrame("Frame", "TacoTipMockPlainFrame")
    local backdrop = createFrame("Frame", "TacoTipMockBackdropFrame", nil, "BackdropTemplate")
    local plainHasNone, backdropHasAll = true, true
    for _, api in ipairs(rule.api) do
        if (plain and plain[api] ~= nil) then plainHasNone = false end
        if (type(backdrop and backdrop[api]) ~= "function") then backdropHasAll = false end
    end
    check("a plain frame carries NO backdrop API, as in the client", plainHasNone,
        "checked " .. tostring(#rule.api) .. " members -- " .. tostring(rule.source))
    check("a BackdropTemplate frame carries the whole backdrop API", backdropHasAll,
        "checked " .. tostring(#rule.api) .. " members -- " .. tostring(rule.source))
    -- The grant has to come from the TEMPLATE, not from the frame's name or
    -- kind, so the mock has to record which template it was asked for.
    -- rawget: this mock's __index answers EVERY unknown key with a function,
    -- so an absent field cannot be read through it.
    check("the mock records the template the client was asked for",
        rawget(backdrop, "__template") == "BackdropTemplate"
            and rawget(plain, "__template") == nil,
        "template=" .. tostring(rawget(backdrop, "__template")))
    return plainHasNone and backdropHasAll
end

-- Resolve the expected arity for the current family.
function M.expected(api, which)
    local spec = M.APIS[api]
    if (not spec) then return nil end
    local v = spec[which or "realArity"]
    if (type(v) == "table") then
        local f = M.family()
        return v[f]
    end
    return v
end

-- How many values does this function publish? Measured by CALLING it and
-- counting what comes back -- select("#", ...) counts the values even when
-- they are nil, which is the whole point: a mock that returns one nil where
-- the client returns seven is exactly the drift this table exists to catch.
--
-- The arguments are passed positionally rather than through "..." so this
-- works on every interpreter: plain Lua 5.1 has a global `unpack` and 5.2+
-- moved it to table.unpack, and the file is loaded before the harness
-- sandbox exists.
function M.measure(fn, a, b, c, d, e, f)
    if (type(fn) ~= "function") then
        return -1
    end
    local ok, n = pcall(function()
        return select("#", fn(a, b, c, d, e, f))
    end)
    if (not ok) then
        return -1
    end
    return n
end

-- Assert one mock against the table.
--
-- check is the MAIN-suite check(name, cond, detail).
function M.assertArity(check, api, mockFn)
    local spec = M.APIS[api]
    if (not spec) then
        check("mock contract knows " .. tostring(api), false, "no contract entry")
        return false
    end
    local real = M.expected(api, "realArity")
    local mock = M.expected(api, "mockArity")
    local p = spec.probe and spec.probe() or {}
    local n = M.measure(mockFn, p[1], p[2], p[3], p[4], p[5], p[6])
    local ok = (n == mock)
    check("mock " .. api .. " publishes " .. tostring(mock) .. " values, as the client does",
        ok, "mockArity=" .. tostring(n) .. " contract=" .. tostring(mock)
            .. " client=" .. tostring(real) .. " -- " .. tostring(spec.source))
    -- A mock that is not the client's arity is a deviation, and a deviation
    -- has to be written down rather than discovered later.
    if (mock ~= real) then
        check("mock " .. api .. " is a DECLARED deviation from the client",
            spec.note ~= nil and spec.note ~= "",
            "contract mockArity=" .. tostring(mock) .. " client realArity=" .. tostring(real)
                .. " -- " .. tostring(spec.source))
    end
    return ok
end

-- A faithful UnitClass mock for the current family.
--
-- classOf(unit) must return the localized class name and the class token, or
-- nil for a unit with no class. The modern pair also publishes the class ID
-- (a number), the Classic family does not.
--
-- classIDOf(unit, className) is optional: it supplies the class ID the
-- modern pair publishes. Without it the helper publishes 1.
function M.unitClassMock(classOf, classIDOf)
    local modern = (family == "forever" or family == "retail")
    return function(u)
        local name, token = classOf(u)
        if (modern) then
            local id = classIDOf and classIDOf(u, name) or (token and 1 or nil)
            return name, token, id
        end
        return name, token
    end
end

return M
