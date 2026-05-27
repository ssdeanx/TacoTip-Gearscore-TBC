--[[

    LibDetours-1.0 by kebabstorm

    Requires: LibStub
    Version: 1 (2022-08-19)

--]]

assert(LibStub, "LibDetours requires LibStub")

local lib = LibStub:NewLibrary('LibDetours-1.0', 1)

-- already loaded
if (not lib) then
    return
end

local function nop()
end

local function getTargetKey(funcTable, funcName)
    if (funcTable) then
        return tostring(funcTable).."__"..funcName
    end
    return funcName
end

local function hasCallableTarget(funcTable, funcName)
    local target = funcTable and funcTable[funcName] or _G[funcName]
    return type(target) == "function"
end

function lib:SecureHook(addon, arg1, arg2, arg3)
    assert(type(addon) == "table", "invalid argument addon: not a table")
    assert(addon ~= lib, "invalid argument addon: can not be self")
    addon.hooks = addon.hooks or {}

    local funcTable, funcName, func, isHookInstalled
    if (type(arg1) == "table") then
        funcTable = arg1
        funcName = arg2
        func = arg3
        isHookInstalled = (addon.hooks[tostring(funcTable).."__"..funcName] ~= nil)
    else
        funcName = arg1
        func = arg2
        isHookInstalled = (addon.hooks[funcName] ~= nil)
    end
    local isHookBeingRemoved = (func == nil)
    if (not isHookInstalled and isHookBeingRemoved) then
        return
    end
    if (not isHookInstalled and not isHookBeingRemoved and not hasCallableTarget(funcTable, funcName)) then
        return nil
    end
    local targetKey = getTargetKey(funcTable, funcName)
    if (funcTable) then
        if (isHookBeingRemoved) then
            addon.hooks[targetKey] = nop
        else
            addon.hooks[targetKey] = func
        end
    else
        if (isHookBeingRemoved) then
            addon.hooks[targetKey] = nop
        else
            addon.hooks[targetKey] = func
        end
    end
    if (not isHookInstalled) then
        if (funcTable) then
            hooksecurefunc(funcTable, funcName, function(...)
                return addon.hooks[targetKey](...)
            end)
        else
            hooksecurefunc(funcName, function(...)
                return addon.hooks[targetKey](...)
            end)
        end
    end
end
function lib:SecureUnhook(addon, arg1, arg2)
    if (type(arg1) == "table") then
        lib:SecureHook(addon, arg1, arg2, nil)
    else
        lib:SecureHook(addon, arg1, nil)
    end
end

function lib:DetourHook(addon, arg1, arg2, arg3)
    assert(type(addon) == "table", "invalid argument addon: not a table")
    assert(addon ~= lib, "invalid argument addon: can not be self")
    addon.detours = addon.detours or {}

    local funcTable, funcName, func, isDetourInstalled
    if (type(arg1) == "table") then
        funcTable = arg1
        funcName = arg2
        func = arg3
        isDetourInstalled = (addon.detours[tostring(funcTable).."__"..funcName] ~= nil)
    else
        funcName = arg1
        func = arg2
        isDetourInstalled = (addon.detours[funcName] ~= nil)
    end
    local isDetourBeingRemoved = (func == nil)
    if (not isDetourInstalled and isDetourBeingRemoved) then
        return
    end
    if (not isDetourInstalled and not isDetourBeingRemoved and not hasCallableTarget(funcTable, funcName)) then
        return nil
    end
    local targetKey = getTargetKey(funcTable, funcName)
    if (funcTable) then
        if (not isDetourInstalled) then
            addon.detours[targetKey] = funcTable[funcName]
        end
        if (isDetourBeingRemoved) then
            funcTable[funcName] = addon.detours[targetKey]
            addon.detours[targetKey] = nil
        else
            funcTable[funcName] = func
            return addon.detours[targetKey]
        end
    else
        if (not isDetourInstalled) then
            addon.detours[targetKey] = _G[funcName]
        end
        if (isDetourBeingRemoved) then
            rawset(_G, funcName, addon.detours[targetKey])
            addon.detours[targetKey] = nil
        else
            rawset(_G, funcName, func)
            return addon.detours[targetKey]
        end
    end
end
function lib:DetourUnhook(addon, arg1, arg2)
    if (type(arg1) == "table") then
        lib:DetourHook(addon, arg1, arg2, nil)
    else
        lib:DetourHook(addon, arg1, nil)
    end
end

function lib:ScriptHook(addon, arg1, arg2, arg3)
    assert(type(addon) == "table", "invalid argument addon: not a table")
    assert(addon ~= lib, "invalid argument addon: can not be self")
    assert(type(arg1) == "table", "invalid argument arg1: not a table")
    assert(type(arg1.HookScript) == "function", "invalid argument arg1: method HookScript does not exist")
    addon.shooks = addon.shooks or {}

    local funcTable = arg1
    local funcName = arg2
    local func = arg3
    local isScriptHookInstalled = (addon.shooks[tostring(funcTable).."__"..funcName] ~= nil)
    local isScriptHookBeingRemoved = (func == nil)
    if (not isScriptHookInstalled and isScriptHookBeingRemoved) then
        return
    end
    local targetKey = getTargetKey(funcTable, funcName)
    if (isScriptHookBeingRemoved) then
        addon.shooks[targetKey] = nop
    else
        addon.shooks[targetKey] = func
    end
    if (not isScriptHookInstalled) then
        funcTable:HookScript(funcName, function(...)
            return addon.shooks[targetKey](...)
        end)
    end
end
function lib:ScriptUnhook(addon, arg1, arg2)
    lib:ScriptHook(addon, arg1, arg2, nil)
end
