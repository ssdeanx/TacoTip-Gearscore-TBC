local _, namespace = ...

if type(namespace) ~= "table"
    or type(namespace.Scoring) ~= "table"
    or type(namespace.Cache) ~= "table" then
    return
end

local Scoring = namespace.Scoring
local Cache = namespace.Cache
local Scanner = {}
namespace.Scanner = Scanner

-- The number of gem positions an item link carries. Scoring owns that number
-- -- its link parser reads EXACTLY three gem fields -- and exports it, so the
-- bound has ONE source of truth instead of a second literal here. The
-- fallback is the same three: if Scoring's export were ever missing, the
-- bound would still be the parser's own count and not a second opinion.
local SOCKET_POSITIONS = Scoring.SOCKET_POSITIONS or 3

local REQUIRED_SLOTS = {
    1, 2, 3, 5, 6, 7, 8, 9, 10,
    11, 12, 13, 14, 15, 16, 17, 18,
}

-- Stage 4: the canonical slot order is inspectable (RankSync builds the
-- sparse slot=itemID run in this order; a parity check pins it against
-- RankDB.GEAR_SLOTS). The list itself is frozen -- the scorer input and the
-- session lifecycle are not retuned by gear sync.
Scanner.REQUIRED_SLOTS = REQUIRED_SLOTS

-- The socket capacity: where it comes from, and what it may not be.
--
-- It used to be the SUM of the stat table's EMPTY_SOCKET* values, read from
-- GetItemStats. Those key names are ENGINE-side: the FrameXML mirror
-- (/home/sam/wow-ui-source) has ZERO occurrences of "EMPTY_SOCKET" -- in any
-- case, on every branch -- so the mirror could neither confirm the names nor
-- say whether the values count socket SLOTS or socket EMPTIES. The only
-- evidence for them was the harness's own client mock, and the mock wrote a
-- FIXED "EMPTY_SOCKET1", "EMPTY_SOCKET2", "EMPTY_SOCKET3" triple for every
-- link. A fixed triple is not a socket count: it is the same three slots for
-- every item, so a one-socket item published TWO empty sockets where the
-- truth is zero, a sockless item published THREE where the truth is zero,
-- and the published Potential GS, Delta and Completion came out above what
-- the item justified.
--
-- The capacity now comes from the DOCUMENTED API, in the call shape Blizzard
-- itself uses:
--
--   origin/live:Interface/AddOns/Blizzard_APIDocumentationGenerated/ItemDocumentation.lua:854
--     Name = "GetItemNumSockets", Type = "Function",
--     Arguments = { { Name = "itemInfo", Type = "ItemInfo", Nilable = false } },
--     Returns  = { { Name = "socketCount", Type = "number", Nilable = false } },
--   origin/forever: the same file at :876
--   origin/classic_era: the same file at :586 (and the same line on
--     origin/classic_anniversary and origin/classic_titan)
--
-- The generated docs name the argument "itemInfo" -- an opaque item handle --
-- and do not say how to build one from a link. Blizzard's own code answers
-- that: it passes the RAW ITEM LINK.
--
--   origin/live:Interface/AddOns/Blizzard_UIPanels_Game/Mainline/PaperDollFrame.lua:1728
--     self.SocketDisplay:SetItem(GetInventoryItemLink("player", self:GetID()));
--   :2766
--     function PaperDollItemSocketDisplayMixin:SetItem(item)
--   :2775
--     local numSockets = C_Item.GetItemNumSockets(item);
--
-- "item" there IS the link string GetInventoryItemLink returned, and it goes
-- straight into C_Item.GetItemNumSockets -- so the link IS the itemInfo
-- argument, and the add-on already holds that link (nativeLink).
--
-- The sibling API is C_Item.GetItemGemID(itemInfo, index)
-- (ItemDocumentation.lua:512 on origin/live, :534 on origin/forever, :321 on
-- origin/classic_era), indexed from ONE over the socket positions:
-- PaperDollFrame.lua:2777-2780 loops "for index, slot in ipairs(self.Slots)"
-- and reads "C_Item.GetItemGemID(item, index)". It is NOT used to publish a
-- number here: it answers for the item TEMPLATE, while the add-on's gems come
-- from the EQUIPPED item's link, so the link stays the cross-check.
--
-- The SCOPE GATE is unchanged. GetItemStats is a MAINLINE-FAMILY API
-- (documented on origin/live and origin/forever, and absent from the whole
-- Interface tree of classic_era, classic_anniversary and classic_titan), and
-- the socket path is still gated on it -- so Classic Era, TBC Anniversary and
-- Titanforge keep their shipped, documented degradation: the empty-socket
-- count, the completion percentage and the potential total are omitted rather
-- than guessed. C_Item.GetItemNumSockets is documented on the Classic
-- branches too, and the gate deliberately does NOT widen to it: widening it
-- would change published numbers on clients that cannot be tested before
-- publish.
local ITEM_CLASS_WEAPON = 2
local WEAPON_SUBCLASS_MAX = 20
local SCOPE_CAPABLE_WEAPON_SUBCLASSES = {
    [2] = true,
    [3] = true,
    [18] = true,
}

-- The scoring policy, from the settings owner.
--
-- The scorer takes the policy as an argument and used to get none: every
-- evaluation therefore ran under its own internal default (restricted to level
-- 70), which is why the three enhancement metrics were computed as BLOCKED for
-- every player on every client no matter what the Options checkbox said.
--
-- Core.lua loads before this file (TacoTip_Extras.toc), so the settings owner
-- is always present in game. The fallback below is the SHIPPED default
-- (restricted), stated explicitly rather than left to the scorer's own
-- internal default -- and it is a POLICY, not a nil policy, so the scorer
-- never sees the "no policy" case by accident.
local DEFAULT_ENHANCEMENT_POLICY = {
    restrictEnhancementMetricsToLevel70 = true,
}

local function enhancementPolicy()
    local core = namespace.Core
    if type(core) == "table" and type(core.GetEnhancementPolicy) == "function" then
        local ok, policy = pcall(core.GetEnhancementPolicy)
        if ok and type(policy) == "table" then
            return policy
        end
    end
    return {
        restrictEnhancementMetricsToLevel70 =
            DEFAULT_ENHANCEMENT_POLICY.restrictEnhancementMetricsToLevel70,
    }
end

local CLASS_IDS = {
    WARRIOR = 1, PALADIN = 2, HUNTER = 3, ROGUE = 4, PRIEST = 5,
    DEATHKNIGHT = 6, SHAMAN = 7, MAGE = 8, WARLOCK = 9, MONK = 10,
    DRUID = 11, DEMONHUNTER = 12, EVOKER = 13,
}
local generation = 0
local initialized = false
local pendingItems = {}
local listeners = {}
local currentState = { status = "idle", generation = 0 }
local inspector
local remoteGeneration = 0
local remoteContexts = {}

local function complete(value)
    return { status = "complete", value = value }
end

local function blocked(status, reason)
    return { status = status, reason = reason }
end

local function isFiniteNumber(value)
    return type(value) == "number"
        and value == value
        and value ~= math.huge
        and value ~= -math.huge
end

local function isNonnegativeInteger(value)
    return isFiniteNumber(value) and value >= 0 and value % 1 == 0
end

local function isPositiveInteger(value)
    return isNonnegativeInteger(value) and value > 0
end

-- Listener fan-out failures (final hunter M-3).
--
-- The fan-out is pcall-guarded on purpose: a raising listener must not stop
-- the other listeners and must not abort the state transition that has
-- already been committed. But the guard made the failure INVISIBLE -- the
-- new state was already published when the listener raised, so the update was
-- lost with nothing said and nothing counted. Counted here with the last
-- message kept, and printed by /ttgsdebug (Core.lua).
local listenerErrors = 0
local lastListenerError = nil

-- Capture failures (the remote capture path).
--
-- The capture runs INSIDE the library's INVENTORY_READY dispatch: the library
-- fires that event from its own INSPECT_READY handler and releases its
-- pending inspect slot only AFTER the callbacks have run. So a raise from the
-- capture path escapes into the library's dispatch, and the library's own
-- release is then skipped -- the queue stops issuing inspects and no unit
-- scores again until the client is reloaded.
--
-- The capture is therefore guarded, and the failure is COUNTED with its
-- message kept: a prevented raise that leaves no trace is exactly the
-- "silent failure" this repository forbids. Counted here, printed by
-- /ttgsdebug (Core.lua).
local captureErrors = 0
local lastCaptureError = nil

local function recordCaptureError(err)
    captureErrors = captureErrors + 1
    lastCaptureError = tostring(err)
end

local function transition(nextState)
    local pendingItemCount = 0
    for _ in pairs(pendingItems) do
        pendingItemCount = pendingItemCount + 1
    end
    nextState.pendingItemCount = pendingItemCount
    currentState = nextState
    for listener in pairs(listeners) do
        local ok, err = pcall(listener, nextState)
        if not ok then
            listenerErrors = listenerErrors + 1
            lastListenerError = tostring(err)
        end
    end
end

local function requestItemData(
    itemID,
    targetGeneration,
    priorPending,
    nextPending
)
    if nextPending[itemID] == targetGeneration then
        return
    end
    nextPending[itemID] = targetGeneration
    if priorPending[itemID] == targetGeneration then
        return
    end

    if type(C_Item) == "table"
        and type(C_Item.RequestLoadItemDataByID) == "function" then
        pcall(C_Item.RequestLoadItemDataByID, itemID)
    end
end

local function capturePlayerIdentity()
    if type(UnitExists) ~= "function"
        or type(UnitIsPlayer) ~= "function"
        or type(UnitGUID) ~= "function"
        or not UnitExists("player")
        or not UnitIsPlayer("player") then
        return nil, "player-validation-failed"
    end

    local guid = UnitGUID("player")
    if type(guid) ~= "string" or guid == "" then
        return nil, "player-guid-unavailable"
    end
    return guid
end

-- Stage-3 cheap-field capture helpers. Everything here is feature-detected
-- and pcall-guarded; anything unresolvable degrades to ""/0, never a raise.
-- Nothing is gated on client identity (repo rule, expansion §6.4.7).

local GUILD_NAME_MAX = 24

-- Guild name for the scanned unit. The engine form is verified with "player"
-- on all five branches (PaperDollFrame.lua:95 classic family,
-- InstanceDifficulty.lua:219 forever / :216 live); the remote-unit form is
-- ASSUMED (no Blizzard call site passes a non-player unit) -- accept only a
-- non-empty string first return, else "". No roster lookup, no new event:
-- blank-until-next-scan is the specified degradation.
local function captureGuildName(unit)
    local getGuild = rawget(_G, "GetGuildInfo")
    if type(getGuild) ~= "function" or type(unit) ~= "string" or unit == "" then
        return ""
    end
    local ok, guildName = pcall(getGuild, unit)
    if not ok or type(guildName) ~= "string" then
        return ""
    end
    -- Sanitize exactly like the store (strip ";" -- a ";" would shift the
    -- wire stride -- and controls), trim, hard-truncate to 24. A multibyte
    -- tail split here is repaired by ValidateRecord at ingest, which never
    -- cuts inside a UTF-8 sequence.
    local clean = guildName:gsub("[%c;]", ""):match("^%s*(.-)%s*$") or ""
    if #clean > GUILD_NAME_MAX then
        clean = clean:sub(1, GUILD_NAME_MAX)
    end
    return clean
end

-- Level from the already-read player cell. The -1 un-inspectable-unit case is
-- absorbed by the >= 1 test without branching on its meaning.
local function captureLevelNumber(levelCell)
    if type(levelCell) == "table" and levelCell.status == "complete"
        and type(levelCell.value) == "number" and levelCell.value >= 1 then
        return math.floor(levelCell.value)
    end
    return 0
end

-- Numeric spec id only, never a localized name. Modern path: the engine's
-- group-aware form (the same call the vendored library resolves in
-- getModernSpecData), then GetInspectSpecialization for inspect targets.
-- Classic-family clients resolve nothing useful here (open question Q3), so
-- the positive-number test below stores 0 rather than inventing an encoding.
-- Never derived by string-matching the localized name.
local function captureSpecID(unit)
    if type(unit) ~= "string" or unit == "" then
        return 0
    end
    local CSI = rawget(_G, "C_SpecializationInfo")
    if type(CSI) == "table" and type(CSI.GetSpecialization) == "function" then
        local isSelf = (unit == "player")
        local ok, id = pcall(CSI.GetSpecialization, not isSelf, false, 1, 1)
        if ok and type(id) == "number" and id > 0 then
            return math.floor(id)
        end
    end
    if type(CSI) == "table" and type(CSI.GetInspectSpecialization) == "function" then
        local ok, id = pcall(CSI.GetInspectSpecialization, unit)
        if ok and type(id) == "number" and id > 0 then
            return math.floor(id)
        end
    end
    return 0
end

-- Retail/Forever wire rule: both PvP fields are 0, always -- never synced,
-- never rendered as inspected. The marker itself lives in Core
-- (`Core.UsesModernPvPSurface`), so the scanner and the leaderboard cannot
-- drift apart: identity decides the family and the rated-BG capability is only
-- the fallback. Keying it on that API alone made a classic client which exposes
-- the modern API as a stub look modern, and silently zeroed the honor rank.
local function modernRatedSurfacePresent()
    local core = namespace.Core
    if type(core) == "table"
        and type(core.UsesModernPvPSurface) == "function" then
        return core.UsesModernPvPSurface() == true
    end
    -- Unreachable in a normal load (Core precedes Scanner); keeps this file
    -- usable in isolation.
    local paperDoll = rawget(_G, "C_PaperDollInfo")
    return type(paperDoll) == "table"
        and type(paperDoll.GetInspectRatedBGData) == "function"
end

-- PvP snapshot at scan-complete time. pvpRank is the Classic Era honor rank
-- number (lifetimeRank, 12th return of GetInspectHonorData) when honor data is
-- already present; arena is the best inspectable rating across brackets (team
-- path playerRating 7th return, teamless path rating 1st return) when honor
-- data is present. Never stalls the scan on INSPECT_HONOR_UPDATE -- a
-- follow-up scan fills it in.
local function capturePvPFields(unit)
    if modernRatedSurfacePresent() then
        return 0, 0
    end
    if type(unit) ~= "string" or unit == "" then
        return 0, 0
    end
    local g = _G
    local hasHonor = rawget(g, "HasInspectHonorData")
    if type(hasHonor) ~= "function" then
        return 0, 0
    end
    local okHas, present = pcall(hasHonor)
    if not okHas or not present then
        return 0, 0
    end
    local pvpRank, arena = 0, 0
    local getHonor = rawget(g, "GetInspectHonorData")
    if type(getHonor) == "function" then
        local honorResults = { pcall(getHonor) }
        local lifetimeRank = honorResults[13]
        if honorResults[1] and type(lifetimeRank) == "number" and lifetimeRank > 0 then
            pvpRank = math.floor(lifetimeRank)
        end
    end
    local getSeason = rawget(g, "GetCurrentArenaSeasonUsesTeams")
    local getTeam = rawget(g, "GetInspectArenaTeamData")
    local getSolo = rawget(g, "GetInspectArenaData")
    local useTeams = false
    if type(getTeam) == "function" then
        if type(getSeason) ~= "function" then
            useTeams = true
        else
            local okSeason, teams = pcall(getSeason)
            useTeams = okSeason and teams == true
        end
    end
    local best = 0
    if useTeams then
        for i = 1, 3 do
            local teamResults = { pcall(getTeam, i) }
            local playerRating = teamResults[8]
            if teamResults[1] and type(playerRating) == "number" and playerRating > best then
                best = playerRating
            end
        end
    end
    if type(getSolo) == "function" then
        for i = 1, 3 do
            local soloResults = { pcall(getSolo, i) }
            local rating = soloResults[2]
            if soloResults[1] and type(rating) == "number" and rating > best then
                best = rating
            end
        end
    end
    if best > 0 then
        arena = math.floor(best)
    end
    return pvpRank, arena
end

local function queueRankSync(guid, unit, classToken, result, sourceTag, levelCell)
    local rankSync = namespace.RankSync
    if type(rankSync) ~= "table" or type(rankSync.QueueInspectRecord) ~= "function" then
        return
    end
    if type(guid) ~= "string" or guid == "" then
        return
    end
    local gs = type(result) == "table"
        and type(result.metrics) == "table"
        and type(result.metrics.gearScore) == "table"
        and result.metrics.gearScore.status == "complete"
        and result.metrics.gearScore.value
    if type(gs) ~= "number" or gs <= 0 then
        return
    end

    local avgMetric = result.metrics.averageItemLevel
    local ilvl = 0
    if type(avgMetric) == "table" and avgMetric.status == "complete" and type(avgMetric.value) == "table" then
        ilvl = avgMetric.value.raw or avgMetric.value.display or 0
    end

    local g = _G
    local pName
    local uName = rawget(g, "UnitName")
    if type(uName) == "function" and unit then
        local ok, n = pcall(uName, unit)
        if ok and type(n) == "string" and n ~= "" then
            pName = n
        end
    end

    local pFaction = "Unknown"
    local uFaction = rawget(g, "UnitFactionGroup")
    if type(uFaction) == "function" and unit then
        local ok, f = pcall(uFaction, unit)
        if ok and (f == "Alliance" or f == "Horde") then
            pFaction = f
        end
    end

    local cToken = (type(classToken) == "table" and classToken.value)
        or (type(classToken) == "string" and classToken)
        or "UNKNOWN"
    local specName, specIcon
    if inspector and unit then
        if type(inspector.GetLocalizedSpecName) == "function" then
            local ok, sName = pcall(inspector.GetLocalizedSpecName, inspector, unit)
            if ok and type(sName) == "string" then
                specName = sName
            end
        end
        if type(inspector.GetLocalizedSpecIcon) == "function" then
            local ok, sIcon = pcall(inspector.GetLocalizedSpecIcon, inspector, unit)
            if ok and sIcon then
                specIcon = sIcon
            end
        end
    end

    -- The server clock, for the record's timestamp. pcall-guarded like every
    -- other client read in this file: this runs inside the library's
    -- INVENTORY_READY dispatch (remote capture) and inside the local scan
    -- (self capture), and an unguarded raise there escaped into the
    -- library's callback dispatch.
    local now = rawget(g, "GetServerTime")
    local ts = 0
    if type(now) == "function" then
        local ok, value = pcall(now)
        if ok and type(value) == "number" then
            ts = value
        end
    end

    -- Stage-3 cheap-field capture (all feature-detected, all pcall-guarded;
    -- anything unresolvable degrades to ""/0, never a raise).
    local guild = captureGuildName(unit)
    local level = captureLevelNumber(levelCell)
    local specID = captureSpecID(unit)
    local pvpRank, arena = capturePvPFields(unit)

    rankSync.QueueInspectRecord({
        guid = guid,
        name = pName or "Unknown",
        faction = pFaction,
        class = cToken,
        classID = CLASS_IDS[cToken] or 0,
        specName = specName or "",
        specIcon = specIcon,
        specID = specID,
        guild = guild,
        level = level,
        pvpRank = pvpRank,
        arena = arena,
        gs = gs,
        ilvl = ilvl,
        timestamp = ts,
        source = sourceTag or "inspect",
    })
end

-- The player's class and level, for the unit under scan.
--
-- Both reads are pcall-guarded, because this function runs INSIDE the
-- library's INVENTORY_READY dispatch: a raise here escapes into the
-- library's callback dispatch, and the library releases its pending inspect
-- slot only AFTER the callbacks have run -- so one unguarded client read
-- cost every add-on (including this one's) its scores until the client was
-- reloaded. Every other client call in this file already degrades instead of
-- raising; these two were the outliers.
--
-- A raising read degrades to the blocked cell the function already builds
-- for an unreadable value, so the scan still publishes a result -- with the
-- class or the level marked unavailable -- instead of dying.
local function capturePlayerCells(unit)
    local classToken
    if type(UnitClass) == "function" then
        local ok, _, token = pcall(UnitClass, unit)
        if ok then
            classToken = token
        end
    end

    local level
    if type(UnitLevel) == "function" then
        local ok, value = pcall(UnitLevel, unit)
        if ok then
            level = value
        end
    end

    local classCell = blocked("unavailable", "player-class-unavailable")
    if type(classToken) == "string" and classToken ~= "" then
        classCell = complete(classToken)
    end

    local levelCell = blocked("unavailable", "player-level-unavailable")
    if isNonnegativeInteger(level) then
        levelCell = complete(level)
    end
    return classCell, levelCell
end

local function captureTemporaryEffects()
    local unavailable = blocked("unavailable", "temporary-weapon-state-unavailable")
    if type(GetWeaponEnchantInfo) ~= "function" then
        return unavailable, unavailable
    end

    local ok, mainHas, _, _, _, offHas =
        pcall(GetWeaponEnchantInfo)
    if not ok then
        return unavailable, unavailable
    end

    local mainCell = unavailable
    local offCell = unavailable
    if type(mainHas) == "boolean" then
        mainCell = complete(mainHas)
    end
    if type(offHas) == "boolean" then
        offCell = complete(offHas)
    end
    return mainCell, offCell
end

local function readSocketCapacity(nativeLink)
    -- THE SCOPE GATE, unchanged. GetItemStats is a MAINLINE-FAMILY API,
    -- present on Retail and WoW Forever and absent from the three Classic
    -- clients (it is documented in
    -- Blizzard_APIDocumentationGenerated/ItemDocumentation.lua on origin/live
    -- and origin/forever, and appears nowhere in the Interface tree of
    -- classic_era, classic_anniversary or classic_titan). Feature-detected, so
    -- the Classic clients take the degraded path rather than a wrong number.
    --
    -- The gate is deliberately NOT widened to C_Item.GetItemNumSockets, which
    -- the mirror documents on the Classic branches too: the Classic clients'
    -- behaviour is a shipped, documented contract, and widening the gate
    -- would change published numbers on clients that cannot be tested before
    -- publish.
    local getItemStats = _G.GetItemStats
    if type(getItemStats) ~= "function" then
        return nil, "socket-capability-unavailable"
    end

    -- THE SOURCE OF TRUTH: the documented socket-count API.
    --
    -- C_Item.GetItemNumSockets(itemInfo) returns the socket count, and the
    -- argument is the item link -- the shape Blizzard itself uses
    -- (PaperDollFrame.lua:2775, fed the raw link at :1728). The evidence is
    -- written out at the top of this file.
    local cItem = _G.C_Item
    if type(cItem) ~= "table" or type(cItem.GetItemNumSockets) ~= "function" then
        return nil, "socket-capacity-unavailable"
    end

    local ok, socketCount = pcall(cItem.GetItemNumSockets, nativeLink)
    if not ok then
        return nil, "socket-capacity-unavailable"
    end
    if not isNonnegativeInteger(socketCount) then
        return nil, "socket-capacity-invalid"
    end
    return socketCount
end

local function buildSocketCell(nativeLink, parsed)
    local capacity, reason = readSocketCapacity(nativeLink)
    if capacity == nil then
        return blocked("unavailable", reason)
    end
    -- An item link carries exactly three gem positions (SOCKET_POSITIONS above
    -- -- Scoring's link parser reads exactly three gem fields), so a capacity
    -- above that cannot be reconciled with the item's own gem list. It is
    -- withheld here rather than published, and Scoring's cross-check rejects
    -- the same shape as a contradiction.
    if capacity > SOCKET_POSITIONS then
        return blocked("unavailable", "socket-capacity-exceeds-gem-list")
    end

    local gemIDs = {}
    for index = 1, capacity do
        gemIDs[index] = parsed.gemIDs[index]
    end
    return complete({ capacity = capacity, gemIDs = gemIDs })
end

local function unavailableMetadata(reason)
    local status = "unavailable"
    return blocked(status, reason), blocked(status, reason), blocked(status, reason),
        blocked(status, reason), blocked(status, reason), blocked(status, reason)
end

local function readMetadata(
    itemID,
    nativeLink,
    targetGeneration,
    priorPending,
    nextPending
)
    if type(C_Item) ~= "table"
        or type(C_Item.GetItemInfo) ~= "function"
        or type(C_Item.GetDetailedItemLevelInfo) ~= "function"
        or type(C_Item.IsItemDataCachedByID) ~= "function" then
        return unavailableMetadata("item-metadata-api-unavailable")
    end

    local cacheOK, cached = pcall(C_Item.IsItemDataCachedByID, itemID)
    if not cacheOK then
        return unavailableMetadata("item-cache-state-unavailable")
    end
    if cached ~= true then
        requestItemData(itemID, targetGeneration, priorPending, nextPending)
        return nil, nil, nil, nil, nil, nil, true
    end

    -- INDEX LAYOUT, and it differs between the two tables below by exactly one.
    --
    -- `{ pcall(f, x) }` builds a table whose element 1 is pcall's success flag,
    -- so everything below is shifted one place right: info[4] is itemQuality,
    -- info[5] itemLevel, info[10] itemEquipLoc, info[13] classID, info[14]
    -- subclassID. That shift is correct for this function's own reads.
    --
    -- TT_GS:GetItemScoreFromInfo does NOT want that table. It indexes the raw
    -- result directly -- scoreFromItemValues(info[2], info[3], info[4], info[9])
    -- for link, quality, level and equipLoc -- so handing it the shifted table
    -- would feed it itemLink for the link field and itemEquipLoc's neighbour for
    -- the equip slot, and every score would come back 0.
    --
    -- So the unshifted result is built separately and carried alongside. The
    -- indices below are the documented C_Item.GetItemInfo return order
    -- (Blizzard_APIDocumentationGenerated/ItemDocumentation.lua):
    --   1 itemName  2 itemLink  3 itemQuality  4 itemLevel  5 itemMinLevel
    --   6 itemType  7 itemSubType  8 itemStackCount  9 itemEquipLoc
    --   10 itemIcon  11 sellPrice  12 classID  13 subclassID
    local info = { pcall(C_Item.GetItemInfo, nativeLink) }
    local detailOK, effectiveItemLevel = pcall(C_Item.GetDetailedItemLevelInfo, nativeLink)
    if not info[1] or not detailOK then
        return unavailableMetadata("item-metadata-read-failed")
    end

    local rawInfo = {}
    for index = 2, #info do
        rawInfo[index - 1] = info[index]
    end

    local quality = info[4]
    local scoringItemLevel = info[5]
    local equipLoc = info[10]
    local itemClassID = info[13]
    local itemSubclassID = info[14]
    if not isNonnegativeInteger(quality)
        or not isFiniteNumber(scoringItemLevel)
        or scoringItemLevel < 0
        or not isFiniteNumber(effectiveItemLevel)
        or effectiveItemLevel < 0
        or type(equipLoc) ~= "string"
        or equipLoc == "" then
        requestItemData(itemID, targetGeneration, priorPending, nextPending)
        return nil, nil, nil, nil, nil, nil, true
    end

    local classCell = blocked("unavailable", "item-class-unavailable")
    if isNonnegativeInteger(itemClassID) then
        classCell = complete(itemClassID)
    end
    local subclassCell = blocked("unavailable", "item-subclass-unavailable")
    if isNonnegativeInteger(itemSubclassID) then
        subclassCell = complete(itemSubclassID)
    end

    -- The unshifted GetItemInfo result travels with the slot so Scoring can hand
    -- it to TT_GS:GetItemScoreFromInfo. That entry point performs no GetItemInfo
    -- call of its own; going through TT_GS:GetItemScore instead would cost one
    -- redundant lookup per item, i.e. 17 per re-scan, on a path that runs on
    -- every equipment change.
    return complete(quality), complete(scoringItemLevel),
        complete(effectiveItemLevel), complete(equipLoc), classCell, subclassCell,
        false, rawInfo
end

local function scopeCapabilityCell(equipLoc, itemClassID, itemSubclassID)
    if type(equipLoc) ~= "table" or equipLoc.status ~= "complete" then
        return blocked("unavailable", "ranged-subtype-unverified")
    end
    if equipLoc.value ~= "INVTYPE_RANGED"
        and equipLoc.value ~= "INVTYPE_RANGEDRIGHT" then
        return complete(false)
    end
    if type(itemClassID) ~= "table"
        or itemClassID.status ~= "complete"
        or itemClassID.value ~= ITEM_CLASS_WEAPON
        or type(itemSubclassID) ~= "table"
        or itemSubclassID.status ~= "complete"
        or not isNonnegativeInteger(itemSubclassID.value)
        or itemSubclassID.value > WEAPON_SUBCLASS_MAX then
        return blocked("unavailable", "ranged-subtype-unverified")
    end
    if SCOPE_CAPABLE_WEAPON_SUBCLASSES[itemSubclassID.value] then
        return complete(true)
    end
    if itemSubclassID.value == 19 then
        return complete(false)
    end
    return blocked("unavailable", "ranged-subtype-unverified")
end

local function temporaryCellForSlot(slotID, mainTemporary, offTemporary)
    if slotID == 16 then
        return mainTemporary
    end
    if slotID == 17 then
        return offTemporary
    end
    return blocked("unavailable", "temporary-weapon-slot-not-applicable")
end

local function buildOccupiedSlot(
    _slotID,
    itemID,
    nativeLink,
    parsed,
    temporaryWeaponEffect,
    targetGeneration,
    priorPending,
    nextPending
)
    local quality, scoringItemLevel, effectiveItemLevel, equipLoc,
        itemClassID, itemSubclassID, isPending, itemInfo =
        readMetadata(
            itemID,
            nativeLink,
            targetGeneration,
            priorPending,
            nextPending
        )

    if isPending then
        return nil, true
    end

    return {
        state = "occupied",
        itemID = complete(itemID),
        nativeLink = complete(nativeLink),
        quality = quality,
        scoringItemLevel = scoringItemLevel,
        effectiveItemLevel = effectiveItemLevel,
        equipLoc = equipLoc,
        itemClassID = itemClassID,
        itemSubclassID = itemSubclassID,
        itemInfoValue = itemInfo,
        permanentEnchantID = complete(parsed.permanentEnchantID),
        scoreGemIDs = complete({
            parsed.gemIDs[1], parsed.gemIDs[2], parsed.gemIDs[3],
        }),
        sockets = buildSocketCell(nativeLink, parsed),
        temporaryWeaponEffect = temporaryWeaponEffect,
        scopeCapablePhysicalRanged = scopeCapabilityCell(
            equipLoc,
            itemClassID,
            itemSubclassID
        ),
    }, false
end

local function captureSlot(
    unit,
    slotID,
    temporaryWeaponEffect,
    targetGeneration,
    priorPending,
    nextPending
)
    -- The two inventory reads are pcall-guarded for the same reason as every
    -- other client read in this file: this function runs inside the library's
    -- INVENTORY_READY dispatch (remote capture) and inside the local scan, and
    -- an unguarded raise there escaped into the library's callback dispatch
    -- and cost the whole session its scores.
    --
    -- A raising read degrades to "no item in this slot": the slot reads as
    -- confirmed-empty, which is the same shape the client's own "no item
    -- there" answer produces.
    local rawItemID
    if type(GetInventoryItemID) == "function" then
        local ok, value = pcall(GetInventoryItemID, unit, slotID)
        if ok then
            rawItemID = value
        end
    end
    local nativeLink
    if type(GetInventoryItemLink) == "function" then
        local ok, value = pcall(GetInventoryItemLink, unit, slotID)
        if ok then
            nativeLink = value
        end
    end

    local effectiveItemID = isPositiveInteger(rawItemID) and rawItemID or nil
    if effectiveItemID == nil and type(nativeLink) == "string" then
        local extracted = string.match(nativeLink, "item:(%d+)")
        local parsedID = extracted and tonumber(extracted) or nil
        if isPositiveInteger(parsedID) then
            effectiveItemID = parsedID
        end
    end

    if effectiveItemID == nil and nativeLink == nil then
        return { state = "confirmed-empty" }, false
    end
    if isPositiveInteger(effectiveItemID) and nativeLink == nil then
        requestItemData(effectiveItemID, targetGeneration, priorPending, nextPending)
        return nil, true
    end
    if not isPositiveInteger(effectiveItemID) or type(nativeLink) ~= "string" then
        return nil, false, "inventory-id-link-contradiction"
    end

    local parsed, parseReason = Scoring.ParseEquippedLink(nativeLink, effectiveItemID)
    if not parsed then
        return nil, false, parseReason or "invalid-native-link"
    end

    local occupied, isPending = buildOccupiedSlot(
        slotID,
        effectiveItemID,
        nativeLink,
        parsed,
        temporaryWeaponEffect,
        targetGeneration,
        priorPending,
        nextPending
    )
    return occupied, isPending
end

local function capture(targetGeneration)
    if targetGeneration ~= generation then
        return
    end

    local startingGUID, identityReason = capturePlayerIdentity()
    if not startingGUID then
        pendingItems = {}
        transition({
            status = "unavailable",
            generation = targetGeneration,
            reason = identityReason,
        })
        return
    end

    local classToken, level = capturePlayerCells("player")
    local mainTemporary, offTemporary = captureTemporaryEffects()
    local priorPending = pendingItems
    local nextPending = {}
    local slots = {}
    local hasPending = false

    for _, slotID in ipairs(REQUIRED_SLOTS) do
        -- The same per-slot guard the remote capture uses (Scanner.lua's
        -- captureRemote). Without it a raise in one slot aborted the whole
        -- local scan, and the scanner stayed "pending" for the rest of the
        -- session -- which is what a player sees as "the tooltip stopped
        -- showing scores".
        local callOK, slot, slotPending, fatalReason = pcall(
            captureSlot,
            "player",
            slotID,
            temporaryCellForSlot(slotID, mainTemporary, offTemporary),
            targetGeneration,
            priorPending,
            nextPending
        )
        if not callOK then
            recordCaptureError(slot)
            pendingItems = {}
            transition({
                status = "unavailable",
                generation = targetGeneration,
                reason = "inventory-read-failed",
            })
            return
        end
        if fatalReason then
            pendingItems = {}
            transition({
                status = "unavailable",
                generation = targetGeneration,
                reason = fatalReason,
            })
            return
        end
        if slotPending then
            hasPending = true
        else
            slots[slotID] = slot
        end
    end

    if targetGeneration ~= generation then
        return
    end

    local endingGUID = capturePlayerIdentity()
    if endingGUID ~= startingGUID then
        pendingItems = {}
        transition({
            status = "unavailable",
            generation = targetGeneration,
            reason = "player-identity-changed",
        })
        return
    end

    pendingItems = nextPending
    if hasPending then
        transition({
            status = "pending",
            generation = targetGeneration,
            reason = "item-data-pending",
        })
        return
    end

    local revision = {
        classToken = classToken,
        level = level,
        socketCapability = complete(type(GetItemStats) == "function"),
        slots = slots,
    }
    local result = Scoring.Evaluate(revision, enhancementPolicy())

    if targetGeneration ~= generation then
        return
    end

    pendingItems = {}
    transition({
        status = "complete",
        generation = targetGeneration,
        revision = revision,
        result = result,
    })
    local playerGUID = capturePlayerIdentity()
    if playerGUID then
        queueRankSync(playerGUID, "player", classToken, result, "self", level)
        -- Stage 4: re-persist the owner's own gear into the bounded RankDB
        -- gear table on every own scan, so the local row survives the
        -- count-eviction the age prune still applies to. Guarded end to end:
        -- a missing RankSync/RankDB, an unserializable revision, or a store
        -- refusal never raises and never stalls the scan. Remote scans never
        -- persist here -- peers answer from a fresh session entry only, and
        -- their gear arrives via D ingest.
        if namespace.RankSync
            and type(namespace.RankSync.BuildGearBlob) == "function"
            and namespace.RankDB
            and type(namespace.RankDB.StoreGear) == "function" then
            local okBlob, blob = pcall(namespace.RankSync.BuildGearBlob, revision.slots)
            if okBlob and type(blob) == "string" then
                local serverClock = rawget(_G, "GetServerTime")
                local gearT = 0
                if type(serverClock) == "function" then
                    local okClock, nowValue = pcall(serverClock)
                    if okClock and type(nowValue) == "number" then
                        gearT = nowValue
                    end
                end
                pcall(namespace.RankDB.StoreGear, playerGUID, gearT, blob)
            end
        end
    end
end

local function isRemotePlayerGUID(guid)
    if type(guid) ~= "string"
        or not string.match(guid, "^Player%-%d+%-%x+$") then
        return false
    end

    if type(GUIDIsPlayer) == "function" then
        local ok, isPlayer = pcall(GUIDIsPlayer, guid)
        if not ok or not isPlayer then
            return false
        end
    end
    return true
end

local function unitMatchesRemoteGUID(unit, guid)
    if type(unit) ~= "string"
        or unit == ""
        or type(UnitExists) ~= "function"
        or type(UnitIsPlayer) ~= "function"
        or type(UnitGUID) ~= "function" then
        return false
    end

    local existsOK, exists = pcall(UnitExists, unit)
    local playerOK, isPlayer = pcall(UnitIsPlayer, unit)
    local guidOK, unitGUID = pcall(UnitGUID, unit)
    if not existsOK or not exists
        or not playerOK or not isPlayer
        or not guidOK or unitGUID ~= guid then
        return false
    end

    local localOK, localGUID = pcall(UnitGUID, "player")
    return not localOK or localGUID ~= guid
end

local function resolveRemoteUnit(guid, callbackUnit)
    if unitMatchesRemoteGUID(callbackUnit, guid) then
        return callbackUnit
    end

    local inspectFrame = _G.InspectFrame
    if type(inspectFrame) == "table"
        and unitMatchesRemoteGUID(inspectFrame.unit, guid) then
        return inspectFrame.unit
    end

    if type(inspector) ~= "table"
        or type(inspector.PlayerGUIDToUnitToken) ~= "function" then
        return nil
    end

    local ok, resolved = pcall(
        inspector.PlayerGUIDToUnitToken,
        inspector,
        guid
    )
    if ok and unitMatchesRemoteGUID(resolved, guid) then
        return resolved
    end
    return nil
end

local function remoteContextIsCurrent(context)
    return remoteContexts[context.guid] == context
        and Cache.IsCurrentGeneration(context.guid, context.generation)
end

local function failRemote(context, reason)
    if not remoteContextIsCurrent(context) then
        return false
    end
    Cache.PublishUnavailable(context.guid, context.generation, reason)
    remoteContexts[context.guid] = nil
    return true
end

-- The remote capture, guarded.
--
-- The body below runs inside the library's INVENTORY_READY dispatch, so a
-- raise here escapes into the library and costs the whole session its
-- inspects. The wrapper is the boundary: the raise is caught, COUNTED with
-- its message kept, and the cache entry is published as unavailable so it
-- does not sit "pending" for the rest of the session.
local captureRemoteBody

local function captureRemote(context)
    local ok, published = pcall(captureRemoteBody, context)
    if not ok then
        recordCaptureError(published)
        failRemote(context, "capture-failed")
        return false
    end
    return published
end

captureRemoteBody = function(context)
    if not remoteContextIsCurrent(context) then
        return false
    end
    if type(GetInventoryItemID) ~= "function"
        or type(GetInventoryItemLink) ~= "function" then
        return failRemote(context, "inventory-api-unavailable")
    end

    local unit = resolveRemoteUnit(context.guid, context.unit)
    if not unit then
        return failRemote(context, "remote-unit-unavailable")
    end
    context.unit = unit

    local classToken, level = capturePlayerCells(unit)
    local priorPending = context.pendingItems
    local nextPending = {}
    local slots = {}
    local hasPending = false
    local remoteTemporary = blocked(
        "unavailable",
        "remote-temporary-weapon-state-unavailable"
    )

    for _, slotID in ipairs(REQUIRED_SLOTS) do
        local callOK, slot, slotPending, fatalReason = pcall(
            captureSlot,
            unit,
            slotID,
            remoteTemporary,
            context.generation,
            priorPending,
            nextPending
        )
        if not callOK then
            return failRemote(context, "inventory-read-failed")
        end
        if fatalReason then
            return failRemote(context, fatalReason)
        end
        if slotPending then
            hasPending = true
        else
            slots[slotID] = slot
        end
    end

    if not remoteContextIsCurrent(context) then
        return false
    end
    if not unitMatchesRemoteGUID(unit, context.guid) then
        return failRemote(context, "remote-identity-changed")
    end

    context.pendingItems = nextPending
    if hasPending then
        Cache.SetPending(
            context.guid,
            context.generation,
            nextPending,
            "item-data-pending"
        )
        return true
    end

    local revision = {
        classToken = classToken,
        level = level,
        socketCapability = complete(type(GetItemStats) == "function"),
        slots = slots,
    }
    local result = Scoring.Evaluate(revision, enhancementPolicy())

    if not remoteContextIsCurrent(context)
        or not unitMatchesRemoteGUID(unit, context.guid) then
        return failRemote(context, "remote-identity-changed")
    end

    local published = Cache.PublishComplete(
        context.guid,
        context.generation,
        revision,
        result
    )
    if published then
        remoteContexts[context.guid] = nil
        queueRankSync(context.guid, unit, classToken, result, "inspect", level)
    end
    return published
end

local function handleRemoteItemDataLoad(itemID, succeeded)
    local matchingGUIDs = {}
    for guid, context in pairs(remoteContexts) do
        if context.pendingItems[itemID] == context.generation
            and remoteContextIsCurrent(context) then
            matchingGUIDs[#matchingGUIDs + 1] = guid
        end
    end
    table.sort(matchingGUIDs)

    local handled = false
    for _, guid in ipairs(matchingGUIDs) do
        local context = remoteContexts[guid]
        if context
            and context.pendingItems[itemID] == context.generation
            and remoteContextIsCurrent(context) then
            handled = true
            if succeeded == false then
                failRemote(context, "item-data-load-failed")
            else
                context.pendingItems[itemID] = nil
                captureRemote(context)
            end
        end
    end
    return handled
end

function Scanner.Initialize(activeInspector)
    initialized = true
    if type(activeInspector) == "table" then
        inspector = activeInspector
    end
end

function Scanner.HandleInventoryReady(event, guid, isInspect, unit)
    if not initialized
        or event ~= "INVENTORY_READY"
        or (isInspect ~= nil and isInspect ~= true)
        or not isRemotePlayerGUID(guid) then
        return false
    end

    local resolved = resolveRemoteUnit(guid, unit)
    if not resolved then
        return false
    end

    remoteGeneration = remoteGeneration + 1
    local context = {
        guid = guid,
        generation = remoteGeneration,
        unit = resolved,
        pendingItems = {},
    }
    remoteContexts[guid] = context

    local began, evictedGUID = Cache.Begin(
        guid,
        context.generation,
        "inventory-ready"
    )
    if evictedGUID then
        remoteContexts[evictedGUID] = nil
    end
    if not began then
        remoteContexts[guid] = nil
        return false
    end

    captureRemote(context)
    return true
end

function Scanner.BeginGeneration(reason)
    generation = generation + 1
    pendingItems = {}
    transition({
        status = "pending",
        generation = generation,
        reason = reason or "scan-requested",
    })
    return generation
end

function Scanner.RunGeneration(targetGeneration)
    if not initialized or targetGeneration ~= generation then
        return false
    end
    capture(targetGeneration)
    return true
end

function Scanner.HandleItemDataLoad(itemID, succeeded)
    if not isPositiveInteger(itemID) then
        return false
    end

    local handled = false
    if pendingItems[itemID] == generation then
        handled = true
        if succeeded == false then
            pendingItems = {}
            transition({
                status = "unavailable",
                generation = generation,
                reason = "item-data-load-failed",
            })
        else
            pendingItems[itemID] = nil
            capture(generation)
        end
    end

    return handleRemoteItemDataLoad(itemID, succeeded) or handled
end

function Scanner.GetCurrent()
    return currentState
end

-- Re-evaluation failures (final silent-failure audit, MEDIUM).
--
-- The scorer is the one piece of the re-evaluation that can raise, and it is
-- the piece that decides the verdict. A raise used to leave the CACHED
-- verdict -- computed under the OLD policy -- exactly where it was, and the
-- caller (Options.lua's level-70 checkbox) discarded even the pcall's
-- boolean. The checkbox flipped, the setting was written, the metrics kept
-- the old verdict, and NOTHING said so: no message, no counter, nothing in
-- /ttgsdebug.
--
-- So the failure is captured, COUNTED, and reported -- once, naming the
-- failure -- and the caller is told how many evaluations failed so it can
-- stop discarding the result.
local reevaluateErrors = 0
local lastReevaluateError = nil

-- Record one re-evaluation failure.
--
-- ONE line per re-evaluation, not one per entry: a scorer that raises raises
-- the same way for every cached entry, so a line per entry would be the same
-- message repeated N times. The counter still counts every one of them.
local function recordReevaluateError(err, announce)
    reevaluateErrors = reevaluateErrors + 1
    lastReevaluateError = tostring(err)
    if announce
        and type(_G.DEFAULT_CHAT_FRAME) == "table"
        and type(_G.DEFAULT_CHAT_FRAME.AddMessage) == "function" then
        pcall(_G.DEFAULT_CHAT_FRAME.AddMessage, _G.DEFAULT_CHAT_FRAME,
            "|cffff5555TacoTip Extras:|r score re-evaluation failed: "
                .. tostring(err)
                .. " (the metrics still show the previous result)")
    end
end

-- Re-evaluate the cached results under the CURRENT scoring policy.
--
-- The level-70 gate is part of the SCORED result, not of the render, so a
-- settings change cannot be honoured by re-rendering what is already cached:
-- the cached result was computed under the old policy, and it would keep
-- reading the old verdict -- "Unavailable" for a value the user has just
-- switched on, or a value the user has just switched off.
--
-- The revision is the immutable input, so the honest fix is to re-run the
-- scorer over the cached revision: no rescan, no re-inspection, no new item
-- data. The local scan and every cached remote entry are both re-evaluated,
-- because both are rendered by the same surfaces (the player tooltip and the
-- Character / Inspect summaries).
--
-- Returns TWO values: the number of results replaced, and the number of
-- evaluations that FAILED. The second value is what stops the caller from
-- discarding the outcome -- a caller that ignores it would go on believing
-- the toggle had taken effect.
function Scanner.Reevaluate()
    local policy = enhancementPolicy()
    local replaced = 0
    local failed = 0
    local announced = false

    -- The one place the scorer is called. A raise is captured, counted and
    -- reported here, and the entry is LEFT ALONE rather than replaced with
    -- something that is not a result.
    local function evaluate(revision)
        local ok, result = pcall(Scoring.Evaluate, revision, policy)
        if not ok then
            failed = failed + 1
            recordReevaluateError(result, not announced)
            announced = true
            return nil
        end
        if type(result) ~= "table" then
            failed = failed + 1
            recordReevaluateError("the scorer returned no result", not announced)
            announced = true
            return nil
        end
        return result
    end

    if type(currentState) == "table"
        and currentState.status == "complete"
        and type(currentState.revision) == "table" then
        local result = evaluate(currentState.revision)
        if type(result) == "table" then
            currentState.result = result
            replaced = replaced + 1
            for listener in pairs(listeners) do
                pcall(listener, currentState)
            end
        end
    end

    if type(Cache.ReevaluateAll) == "function" then
        -- The evaluator is the guarded one above, so Cache's own pcall cannot
        -- swallow the failure: the raise is already counted and reported by
        -- the time Cache sees it, and the entry is left alone because the
        -- guarded evaluator returns nil.
        local ok, count = pcall(Cache.ReevaluateAll, evaluate)
        if ok and type(count) == "number" then
            replaced = replaced + count
        elseif not ok then
            failed = failed + 1
            recordReevaluateError(count, not announced)
            announced = true
        end
    end

    return replaced, failed
end

-- Scan progress, for the status bars.
--
-- The signal already existed and was simply not published: transition() records
-- `pendingItemCount` on every state change, and the status says whether a scan
-- is running. Two callers (the leaderboard header and the Options page) need the
-- same shape, so it is computed once here rather than twice from internals.
--
-- `REQUIRED_SLOTS` is the denominator, not the number of pending ITEM ids: one
-- slot resolves to one item, so counting items against slots is the same scale.
-- The completeness rule matters -- a scan with nothing pending is COMPLETE even
-- if the status has not flipped yet, because otherwise the bar sits at 99% and
-- looks stuck.
function Scanner.GetProgress()
    local state = currentState or {}
    local status = state.status or "idle"
    local pending = tonumber(state.pendingItemCount) or 0
    local total = #REQUIRED_SLOTS
    if total <= 0 then
        total = 1
    end

    local done = total - pending
    if done < 0 then done = 0 end
    if done > total then done = total end

    local percent
    if pending == 0 and (status == "complete" or status == "unavailable") then
        percent = 1
    elseif status == "idle" then
        percent = 0
    else
        percent = done / total
    end

    return {
        status = status,
        generation = state.generation or 0,
        pending = pending,
        total = total,
        done = done,
        percent = percent,
        active = (status == "pending"),
    }
end

function Scanner.Subscribe(listener)
    if type(listener) ~= "function" then
        return false
    end
    listeners[listener] = true
    return true
end

function Scanner.Unsubscribe(listener)
    listeners[listener] = nil
end

-- Debug accessor for the listener fan-out counter above (read-only). Printed
-- by /ttgsdebug (Core.lua) and read by the harness.
function Scanner.GetDebugState()
    return {
        listenerErrors = listenerErrors,
        lastListenerError = lastListenerError,
        reevaluateErrors = reevaluateErrors,
        lastReevaluateError = lastReevaluateError,
        captureErrors = captureErrors,
        lastCaptureError = lastCaptureError,
    }
end

function Scanner.GetRemote(guid)
    return Cache.Get(guid)
end

function Scanner.GetFreshRemote(guid)
    return Cache.GetFresh(guid)
end

function Scanner.SubscribeRemote(listener)
    return Cache.Subscribe(listener)
end

function Scanner.UnsubscribeRemote(listener)
    Cache.Unsubscribe(listener)
end
