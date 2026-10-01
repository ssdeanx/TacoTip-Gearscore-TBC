-- Load the real library; simulate delayed replies, other addons and mutable tokens.
local root = os.getenv("TACOTIP_TEST_ROOT") or "."
local profiles = {{2,11509,"ERA"},{5,20506,"TBC"},{11,38002,"TITANFORGE"},{1,16001,"FOREVER"},{1,120100,"RETAIL"}}
local function setup(profile)
    local s = {now=100, shown=false, combat=false, requests={}, errors={}, gear={}, textures={}, reads=0, clears=0, ranges={}, uiErrors={}, inspectChecks=0,
        units={player="Player-P", target="Player-A", mouseover="Player-B", party1="Player-C"}, secret={}}
    for _, guid in pairs(s.units) do s.gear[guid] = {[1]="item:"..guid} end
    local e = setmetatable({}, {__index=_G}); e._G=e
    e.WOW_PROJECT_ID=profile[1]
    e.WOW_PROJECT_MAINLINE,e.WOW_PROJECT_CLASSIC=1,2
    e.WOW_PROJECT_BURNING_CRUSADE_CLASSIC,e.WOW_PROJECT_WRATH_CLASSIC=5,11
    e.GetBuildInfo=function() return "test","build","date",profile[2] end
    e.GetTime=function() return s.now end; e.time=e.GetTime
    e.issecretvalue=function(v) return v==s.secret end
    e.UnitGUID=function(u) return s.units[u] end
    e.UnitExists=function(u) return s.units[u]~=nil end; e.UnitIsPlayer=e.UnitExists
    e.UnitIsUnit=function(a,b) return s.units[a]==s.units[b] end
    e.InCombatLockdown=function() return s.combat end
    e.CheckInteractDistance = function(unit, index)
        assert(index == 1, "use inspect interaction distance")
        return s.ranges[unit] ~= false
    end
    e.UIErrorsFrame = {AddMessage = function(_, message)
        s.uiErrors[#s.uiErrors + 1] = message
    end}
    e.CanInspect = function(unit)
        s.inspectChecks = s.inspectChecks + 1
        if s.ranges[unit] == false then
            -- Model an interface message, not a Lua exception caught by pcall.
            e.UIErrorsFrame:AddMessage("Out of Range")
            return false
        end
        return e.UnitExists(unit)
    end
    e.NotifyInspect=function(u) s.requests[#s.requests+1]={guid=e.UnitGUID(u),at=s.now} end
    e.ClearInspectPlayer=function() s.clears=s.clears+1 end
    e.hooksecurefunc=function(name,hook)
        local original=assert(e[name]); e[name]=function(...) original(...);hook(...) end
    end
    e.InspectFrame={unit="party1",IsShown=function() return s.shown end}
    e.CreateFrame=function()
        local f={scripts={},events={}}
        function f:SetScript(name,fn) self.scripts[name]=fn end
        function f:RegisterEvent(name) self.events[name]=true end
        return f
    end
    e.GetInventoryItemLink=function(u,slot) local items=s.gear[e.UnitGUID(u)];return items and items[slot] end
    e.GetInventoryItemTexture=function(u,slot)
        local textures=s.textures[e.UnitGUID(u)];return textures and textures[slot] or e.GetInventoryItemLink(u,slot)
    end
    e.GetNumTalents=function() return 1 end
    e.GetTalentInfo=function() s.reads=s.reads+1;return nil,123456,nil,nil,5 end
    e.GetActiveTalentGroup=function() return 1 end
    e.UnitClass=function() return "Warrior","WARRIOR",1 end
    e.UnitSex=function() return 2 end
    e.geterrorhandler=function() return function(err) s.errors[#s.errors+1]=err end end
    if profile[1]==1 then
        e.GetNumTalents, e.GetTalentInfo = nil, nil
        e.C_SpecializationInfo={
            GetSpecialization=function() s.reads=s.reads+1;return 71 end,
            GetClassIDFromSpecID=function() return 1 end,
            GetInspectSpecialization=function() s.reads=s.reads+1;return 71 end,
            GetSpecializationInfo=function(i) return 70+i,"Spec",nil,123456,nil,nil,5 end,
            GetNumSpecializationsForClassID=function() return 3 end,
            GetSpecializationInfoByID=function(id) return id,"Spec",nil,123456,nil,"WARRIOR" end,
            GetActiveSpecGroup=function() return 1 end,
        }
    end
    for _,path in ipairs({"LibStub/LibStub.lua","CallbackHandler-1.0/CallbackHandler-1.0.lua","LibForeverInspector/LibForeverInspector.lua"}) do
        local chunk=assert(loadfile(root.."/Libs/"..path));setfenv(chunk,e);chunk("TacoTip")
    end
    s.lib=e.LibStub("LibForeverInspector");s.env=e
    function s:advance(seconds)
        for _=1,seconds do
            self.now=self.now+1
            local update=self.lib.frame.scripts.OnUpdate
            if update then update(self.lib.frame,1) end
        end
    end
    function s:event(name,value) self.lib.frame.scripts.OnEvent(self.lib.frame,name,value) end
    function s:ready(guid) self:event("INSPECT_READY",guid) end
    return s
end
local cases={
    {"talent cache retains client-specific specialization data",function(s)
        s.lib:DoInspect("target");s:ready("Player-A")
        local data=s.lib.cache["Player-A"]
        assert(data.talentTime==s.now and data.activeGroup==1)
        if s.env.WOW_PROJECT_ID==1 then
            assert(data.specID==71 and data.specName=="Spec" and data.specIndex==1)
        else
            assert(data.talentPoints[1][1]==5 and data.talentPoints[2][1]==5)
        end
    end},
    {"manual inspect has priority",function(s)
        s.shown=true;s.lib:DoInspect("mouseover");s:advance(8);assert(#s.requests==0)
        s:ready("Player-C");assert(s.lib.cache["Player-C"].items[1])
        s.shown=false;s:advance(1);assert(#s.requests==1 and s.requests[1].guid=="Player-B")
    end},
    {"fast mouseover queued without another hover",function(s)
        s.lib:DoInspect("target");s:ready("Player-A");s.lib:DoInspect("mouseover");assert(#s.requests==1)
        s:advance(2);assert(#s.requests==2 and s.requests[2].guid=="Player-B")
    end},
    {"callback repaint does not recurse",function(s)
        s.lib.RegisterCallback("test","INVENTORY_READY",function() s.lib:DoInspect("target") end)
        s.lib:DoInspect("target");s:ready("Player-A");s:advance(3);assert(#s.requests==1)
    end},
    {"queue deduplicates and resumes after combat",function(s)
        s.combat=true;for _=1,20 do s.lib:DoInspect("target") end
        s.combat=false;s:advance(1);s:ready("Player-A");s:advance(3);assert(#s.requests==1)
    end},
    {"timeouts bounded, cooldown prevents spam",function(s)
        s.lib:DoInspect("target");s:advance(16);assert(#s.requests==3)
        for _=1,20 do s.lib:DoInspect("target") end
        s:advance(5);assert(#s.requests==3)
        s:advance(5);s.lib:DoInspect("target");assert(#s.requests==4)
    end},
    {"empty response retries and is not fresh",function(s)
        s.gear["Player-A"]={};s.lib:DoInspect("target");s:ready("Player-A")
        assert(select(2,s.lib:GetLastCacheTime("target"))==0)
        s:advance(2);assert(#s.requests==2)
        s.gear["Player-A"]={[1]="item:loaded"};s:ready("Player-A");s:advance(6);assert(#s.requests==2)
    end},
    {"inventory event fills partial cache without reading talents",function(s)
        s.textures["Player-A"]={[2]=123456};s.lib:DoInspect("target");s:ready("Player-A")
        assert(select(2,s.lib:GetLastCacheTime("target"))==0)
        s.gear["Player-A"][2]="item:neck";local reads=s.reads
        s:event("UNIT_INVENTORY_CHANGED","target")
        assert(s.lib.cache["Player-A"].items[2]=="item:neck" and s.reads==reads)
        s:advance(3);assert(#s.requests==1)
    end},
    {"partial cache preserves old items, complete update removes unequipped item",function(s)
        s.gear["Player-A"][2]="item:neck";s.lib:DoInspect("target");s:ready("Player-A")
        s.gear["Player-A"]={};s:event("UNIT_INVENTORY_CHANGED","target")
        assert(s.lib.cache["Player-A"].items[2]=="item:neck")
        s.gear["Player-A"]={[1]="item:head"};s:event("UNIT_INVENTORY_CHANGED","target")
        assert(s.lib.cache["Player-A"].items[2]==nil)
    end},
    {"GUID queue survives target replacement",function(s)
        s.combat=true;s.lib:DoInspect("target");s.units.party2="Player-A";s.units.target="Player-D"
        s.combat=false;s:advance(1);assert(s.requests[1].guid=="Player-A")
        s:ready("Player-A");assert(s.lib.cache["Player-D"]==nil)
    end},
    {"missing GUID never caches replacement target",function(s)
        s.lib:DoInspect("target");s.units.target="Player-D";s:ready("Player-A");s:advance(6)
        assert(s.lib.cache["Player-A"]==nil and s.lib.cache["Player-D"]==nil and #s.requests==1)
    end},
    {"external request preserves our queued work",function(s)
        s.lib:DoInspect("target");s.env.NotifyInspect("party1");s:advance(2);assert(#s.requests==2)
        s:ready("Player-C");s:advance(1);assert(#s.requests==3 and s.requests[3].guid=="Player-A")
    end},
    {"foreign response does not complete pending request",function(s)
        s.lib:DoInspect("target");s.lib:DoInspect("mouseover");s:ready("Player-C")
        s:advance(2);assert(#s.requests==1);s:ready("Player-A");s:advance(1);assert(#s.requests==2)
    end},
    {"inventory event does not renew stale talent cache",function(s)
        s.lib:DoInspect("target");s:ready("Player-A");s:advance(9);s:event("UNIT_INVENTORY_CHANGED","target")
        assert(not s.lib:DoInspect("target"));s:advance(1);s.lib:DoInspect("target");assert(#s.requests==2)
    end},
    {"GUID input resolves last raid slot",function(s)
        s.units.raid40="Player-Z";s.lib:DoInspect("Player-Z");assert(s.requests[1].guid=="Player-Z")
    end},
    {"restricted GUID and missing API are skipped",function(s)
        s.units.target=s.secret;assert(not s.lib:DoInspect("target"));s:ready(s.secret)
        s.env.NotifyInspect=nil;assert(not s.lib:DoInspect("mouseover"));assert(#s.requests==0)
    end},
    {"nil event not attributed to mutable mouseover",function(s)
        s.lib:DoInspect("mouseover");s.units.mouseover="Player-D";s:ready(nil);assert(s.lib.cache["Player-D"]==nil)
    end},
    {"missing token returns without another hover", function(s)
        s.combat = true
        s.lib:DoInspect("target")
        s.units.target = nil
        s.combat = false
        s:advance(3)
        assert(#s.requests == 0)
        s.units.party2 = "Player-A"
        s:advance(1)
        assert(#s.requests == 1 and s.requests[1].guid == "Player-A")
    end},
    {"temporary CanInspect rejection is deferred", function(s)
        s.env.CanInspect = function() return false end
        s.lib:DoInspect("target")
        s:advance(3)
        assert(#s.requests == 0)
        s.env.CanInspect = s.env.UnitExists
        s:advance(1)
        assert(#s.requests == 1 and s.requests[1].guid == "Player-A")
    end},
    {"temporary CanInspect error is deferred", function(s)
        s.env.CanInspect = function() error("temporarily unavailable") end
        s.lib:DoInspect("target")
        s:advance(3)
        s.env.CanInspect = s.env.UnitExists
        s:advance(1)
        assert(#s.requests == 1 and s.requests[1].guid == "Player-A")
    end},
    {"unavailable request does not block another player", function(s)
        s.combat = true
        s.lib:DoInspect("target")
        s.lib:DoInspect("mouseover")
        s.env.CanInspect = function(unit) return unit ~= "target" end
        s.combat = false
        s:advance(1)
        assert(#s.requests == 1 and s.requests[1].guid == "Player-B")
        s:ready("Player-B")
        s.env.CanInspect = s.env.UnitExists
        s:advance(2)
        assert(#s.requests == 2 and s.requests[2].guid == "Player-A")
    end},
    {"unavailable request expires despite repeated hovers", function(s)
        s.env.CanInspect = function() return false end
        s.lib:DoInspect("target")
        for _ = 1, 20 do
            s:advance(1)
            s.lib:DoInspect("target")
        end
        assert(#s.requests == 0)
        s.env.CanInspect = s.env.UnitExists
        assert(not s.lib:DoInspect("target"), "expired request should be in cooldown")
        s:advance(1)
        assert(#s.requests == 0, "expired request must not remain queued")
        s:advance(5)
        s.lib:DoInspect("target")
        assert(#s.requests == 1)
    end},
    {"distant player waits silently and resumes in range", function(s)
        s.ranges.target = false
        s.lib:DoInspect("target")
        s:advance(4)
        assert(s.inspectChecks == 0 and #s.requests == 0 and #s.uiErrors == 0)
        s.ranges.target = true
        s:advance(1)
        assert(#s.requests == 1 and s.requests[1].guid == "Player-A")
    end},
    {"retry rechecks distance after player moves away", function(s)
        s.lib:DoInspect("target")
        s.ranges.target = false
        s:advance(6)
        assert(s.inspectChecks == 1 and #s.requests == 1 and #s.uiErrors == 0)
        s.ranges.target = true
        s:advance(1)
        assert(#s.requests == 2)
    end},
    {"unknown or restricted distance skips inspect calls", function(s)
        local checks = {
            function() return nil end,
            function() error("restricted") end,
            function() return s.secret end,
        }
        for _, check in ipairs(checks) do
            s.env.CheckInteractDistance = check
            s.lib:DoInspect("target")
            s:advance(1)
        end
        s.env.CheckInteractDistance = nil
        s.lib:DoInspect("target")
        s:advance(1)
        assert(s.inspectChecks == 0 and #s.requests == 0 and #s.uiErrors == 0)
    end},
    {"manual out-of-range errors remain visible", function(s)
        s.ranges.target = false
        s.shown = true
        s.lib:DoInspect("target")
        s.env.CanInspect("target")
        assert(#s.uiErrors == 1 and s.uiErrors[1] == "Out of Range")
        s.uiErrors = {}
    end},
    {"queue is bounded",function(s)
        s.combat=true
        for i=1,25 do s.units["raid"..i]="Player-"..i;s.lib:DoInspect("raid"..i) end
        s.combat=false;s:advance(1);assert(s.requests[1].guid=="Player-6")
    end},
}
local failures,count=0,0
for _,profile in ipairs(profiles) do
    for _,case in ipairs(cases) do
        local ok,err=pcall(function()
            local s=setup(profile);case[2](s)
            assert(#s.errors==0,table.concat(s.errors,"\n"));assert(s.clears==0)
            assert(#s.uiErrors == 0, "unexpected interface error message")
        end)
        count=count+1
        if not ok then failures=failures+1;print("FAIL "..profile[3].." "..case[1]..": "..tostring(err)) end
    end
end
print(string.format("inspect_test: %d scenarios, %d failures",count,failures))
os.exit(failures==0 and 0 or 1)
