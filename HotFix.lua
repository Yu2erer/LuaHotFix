-----------------------------------------------------------
-- 文件名　：HotFix.lua
-- 创建者　：yuerer
-- 创建时间：2020-11-16 10:20:20
-- 说明  　：Lua HotFix Plugin
-----------------------------------------------------------


-- output debug infomation
local isDebug = false

local realEnv = _ENV

local debug = debug
local string = string
local print = print

local getupvalue = debug.getupvalue
local upvaluejoin = debug.upvaluejoin


local function DEBUG(str, ...)
    if isDebug then
        print("[DEBUG] " .. string.format(str, ...))
    end
end

local function WARN(str, ...)
    print("[WARN ] " .. string.format(str, ...))
end

local function ERROR(str, ...)
    print("[ERROR] " .. string.format(str, ...))
end


-------------------------- FakeEnv --------------------------

-- only supports lua 5.3
local function getfenv(f)
    if not f then
        return nil
    end

    local i = 1
    while true do
        local name, value = getupvalue(f, i)
        if name == "_ENV" then
            return value
        elseif not name then
            break
        end
        i = i + 1
    end
end

local function setfenv(f, env)
    if not f then
        return nil
    end

    local i = 1
    while true do
        local name, value = getupvalue(f, i)
        if name == "_ENV" then
            upvaluejoin(f, i, (function()
                return env
            end), 1)
            break
        elseif not name then
            break
        end
        i = i + 1
    end
end

local fakeEnv = {}
local HotFix = {}

function HotFix.Require(modname)
    DEBUG("require: %s", modname)
    local loader, path = HotFix:FindLoader(modname)
    if loader == nil then
        -- pcall can catch it
        error(string.format("require:%s failed", modname))
        return
    end
    setfenv(loader, HotFix.fakeEnv)
    loader()
end

HotFix.innerFunc = {
    require = HotFix.Require,
}

function fakeEnv:New()
    local fEnv = {}
    setmetatable(fEnv, {__index = function(t, k)
        if HotFix.innerFunc[k] then
            return HotFix.innerFunc[k]
        else
            return realEnv[k]
        end
    end})

    return fEnv
end

-------------------------- HotFix --------------------------

-- clone table without function
function HotFix:CloneTable(tb, name)
    local res = {}
    for k, v in pairs(tb) do
        local kType = type(k)
        local vType = type(v)

        if kType == "function" or vType == "function" then
            goto continue
        end
        
        if vType == "table" then
            assert(kType == "string")
            local cbMT = HotFix:CloneTable(v, k)
            local cb = setmetatable({}, cbMT)
            res[k] = cb
            goto continue
        end

        res[k] = v
        ::continue::
    end
    
    res.name = name

    res.__newindex = function(tb, k, v)
        if not name then
            name = "_RELOADENV"
        end
        if not HotFix.reloadMap[name] then
            HotFix.reloadMap[name] = {}
        end
        table.insert(HotFix.reloadMap[name], {k, v})
    end

    res.__index = function(tb, k)
        if res[k] then
            return res[k]
        end
    end

    return res
end

local function _updateValue(oldtb, newtb)
    for _, v in ipairs(newtb) do
        local name = v[1]
        local value = v[2]

        DEBUG("updateValue %s:%s", name, value)
        rawset(oldtb, name, value)
        ::continue::
    end
end

function HotFix:UpdateValue(reloadMap)
    for name, obj in pairs(reloadMap) do
        if name == "_RELOADENV" then
            _updateValue(realEnv, obj)
        else
            if not realEnv[name] then
                ERROR("can not find %s in _ENV", name)
                goto continue
            end
            _updateValue(realEnv[name], obj)
        end
        ::continue::
    end
    
end

-- check chunk type and update chunk
-- module can return a table or function
-- other types? (boolean)
function HotFix:CheckChunkType(oldChunk, chunk)
    local oldChunkType = type(oldChunk)
    local chunkType = type(chunk)

    if oldChunkType ~= "boolean" and oldChunk == chunk then
        ERROR("oldChunk == chunk and not return")
        return false
    end

    if oldChunk ~= nil and oldChunkType ~= chunkType then
        ERROR("oldChunkType:%s != chunkType:%s", oldChunkType, chunkType)
        return false
    end

    DEBUG("chunkType is %s", chunkType)
    
    -- 1. get a new object
    -- 2. compare two objects
    -- maybe a gloabl variable or a function
    for name, newObj in pairs(HotFix.fakeEnv) do
        HotFix.newObjectMap[name] = newObj

        local newObjType = type(newObj)
        local oldObj = rawget(realEnv, name)
        local oldObjType = type(oldObj)

        if newObjType == "function" then
            HotFix:UpdateFunc(name, oldObj, newObj)
        elseif newObjType == "table" then
            if not oldObj then
                oldObj = rawset(realEnv, name, {})
            end
            HotFix:UpdateTable(oldObj, newObj)
        elseif valueType == "userdata" or valueType == "thread" then
            WARN("not support %s, %s", name, valueType)
        else
            if not oldObj then
                DEBUG("automatic updates, objType:%s, name:%s, obj:%s",
                    newObjType, name, tostring(newObj))
                rawset(realEnv, name, newObj)
            else
                WARN("check no automatic updates, objType:%s, name:%s, oldObj:%s, newObj:%s",
                    newObjType, name, tostring(oldObj), tostring(newObj))
            end
        end
    end
    
    -- 3. call __RELOAD function if it exists
    local __reload = HotFix.fakeEnv["__RELOAD"]
    local __reloadType = type(__reload)
    if __reloadType == "nil" then
        return
    elseif __reloadType ~= "function" then
        ERROR("__RELOAD not a function")
        return
    end

    local reloadEnvMT = HotFix:CloneTable(HotFix.fakeEnv)
    setmetatable(reloadEnvMT, {__index = HotFix.fakeEnv})

    local reloadEnv = setmetatable({}, reloadEnvMT)
    setfenv(__reload, reloadEnv)

    local succ = pcall(__reload)
    -- __reload()

    if not succ then
        ERROR("call __RELOAD failed")
    end

    HotFix:UpdateValue(HotFix.reloadMap)
end

-- if find succ, return function and module path
function HotFix:FindLoader(name)
    local errMsg = {}
    for _, loader in ipairs(package.searchers) do
        local succ, ret, path = pcall(loader, name)
        if not succ then
            ERROR("FindLoader:%s", ret)
            return nil
        end

        local retType = type(ret)

        if retType == "function" then
            return ret, path
        elseif retType == "string" then
            table.insert(errMsg, ret)
        end
    end
    ERROR("module:%s not found:%s", name, table.concat(msg))
    return nil
end


function HotFix:UpdateModule(modname)
    if package.loaded[modname] == nil then
        ERROR("module:%s is not exists", modname)
        return
    end
    local loader, path = HotFix:FindLoader(modname)
    if loader == nil then
        ERROR("module:%s can not find path", modname)
        return
    end
    HotFix:UpdateChunk(modname, path)
end

-- modname: package.loaded[?]
-- src: file path
function HotFix:UpdateChunk(modname, src)
    HotFix:Reset()

    local oldChunk = package.loaded[modname]
    if oldChunk == nil then
        ERROR("oldChunk is nil")
        return false
    end
    
    local isNotRetFlag = false
    if type(oldChunk) == "boolean" then
        isNotRetFlag = true
    end
    
    -- must be a chunk or true...
    local ckOrBool = HotFix:BuildChunk(src, isNotRetFlag)

    if not ckOrBool then
        ERROR("UpdateChunk failed")
        return false
    end
    
    -- ckOrBool is a chunk or boolean
    HotFix:CheckChunkType(oldChunk, ckOrBool)
    HotFix:Clear()
end

function HotFix:UpdateFunc(name, oldFunc, newFunc)
    if HotFix.funcMark[name] then
        return
    end
    HotFix.funcMark[name] = true

    DEBUG("--------------- UpdateFunc ----- -----------------")
    DEBUG("UpdateFunc name: %s", name)
    HotFix:UpdateUpvalues(oldFunc, newFunc)
    local env = getfenv(oldFunc) or realEnv
    setfenv(newFunc, env)
    DEBUG("--------------- UpdateFunc END -----------------")

end

function HotFix:UpdateUpvalues(oldFunc, newFunc)
    if not oldFunc then
        DEBUG("not OldFunc")
        return
    end
    DEBUG("--------------- UpdateUpvalues -----------------")
    -- k: name, v: {index, value}
    local upvalueMap = {}
    -- k: name, v: is exists(boolean)
    local nameMap = {}

    local i = 1
    while true do
        local name, value = getupvalue(oldFunc, i)
        if not name then
            break
        end

        DEBUG("old upvalue, %s, %s", name, value)

        upvalueMap[name] = {
            index = i,
            value = value
        }

        nameMap[name] = true
        i = i + 1
    end

    i = 1
    while true do
        local name, value = getupvalue(newFunc, i)
        if not name then
            break
        end

        -- upvalue exists in the oldChunk
        if nameMap[name] then
            local oldValue = upvalueMap[name].value
            local oldValueIndex = upvalueMap[name].index
            local oldValueType = type(oldValue)

            local valueType = type(value)

            DEBUG("new upvalue, name:%s, oldValueType:%s, valueType:%s", name, oldValueType, valueType)

            if oldValueType ~= valueType then
                ERROR("UpdateUpvalues oldValueType:%s != valueType:%s", 
                    oldValueType, valueType)
                goto continue
            end
            
            DEBUG("%s is a %s", name, valueType)

            if valueType == "table" then
                HotFix:UpdateTable(oldValue, value)
                upvaluejoin(newFunc, i, oldFunc, oldValueIndex)
            elseif valueType == "function" then
                HotFix:UpdateFunc(name, oldValue, value)
                DEBUG("UpdateFunc ", name, value)
            elseif valueType == "userdata" or valueType == "thread" then
                WARN("not support %s, %s", name, valueType)
            else
                local tag = string.format("%s %s", tostring(newFunc), tostring(name))
                if HotFix.fixUpvalueMap[tag] == true then
                    goto continue
                end
                DEBUG("upvaluejoin %s, oldValueIndex:%d, type:%s", name, oldValueIndex, oldValueType)
                upvaluejoin(newFunc, i, oldFunc, oldValueIndex)
            end
        else
            DEBUG("set new upvalue, name:%s, value:%s, idx:%d", name, value, i)
            debug.setupvalue(newFunc, i, value)
            local tag = string.format("%s %s", tostring(newFunc), tostring(name))
            HotFix.fixUpvalueMap[tag] = true
        end

        ::continue::
        i = i + 1
    end
    DEBUG("---------------- UpdateUpvalues end-----------------")

end

function HotFix:UpdateTable(oldTable, newTable)
    if oldTable == newTable then
        return
    end

    local tag = string.format("%s %s", tostring(oldTable), tostring(newTable))
    if HotFix.tableMark[tag] then
        DEBUG("UpdateTable is same %s", tag)
        return
    end
    HotFix.tableMark[tag] = true
    
    for name, value in pairs(newTable) do
        local oldValue = rawget(oldTable, name)
        local oldValueType = type(oldValue)

        local valueType = type(value)

        DEBUG("UpdateTable, name:%s, oldValueType:%s newValueType:%s",
            name, oldValueType, valueType)

        if valueType == "function" then
            HotFix:UpdateFunc(name, oldValue, value)
            DEBUG("set oldTable[%s] = %s", name, tostring(value))
            rawset(oldTable, name, value)
        elseif valueType == "table" then
            HotFix:UpdateTable(oldValue, value)
        else
            if oldValue == value then
                goto continue
            end
            if not oldValue then
                DEBUG("set new variable, objType:%s, name:%s, newObj:%s",
                    valueType, name, value)
                rawset(oldTable, name, value)
            else
                WARN("table no automatic updates, objType:%s, name:%s, oldObj:%s, newObj:%s",
                    valueType, name, oldValue, value)
            end
        end

        ::continue::
    end

    if newTable == HotFix.fakeEnv then
        return
    end

    local oldMetaTable = getmetatable(oldTable)
    local metaTable = getmetatable(newTable)
    local oldMetaTableType = type(oldMetaTable)
    local metaTableType = type(metaTable)
    if oldMetaTableType == metaTableType and metaTableType == "table" then
        HotFix:UpdateTable(oldMetaTable, metaTable)
    end
end


-- return chunk
-- when isNotRetFlag == true, return true
function HotFix:BuildChunk(src, isNotRetFlag)
    HotFix.fakeEnv = fakeEnv:New()
    
    local chunk, err = loadfile(src, "bt", HotFix.fakeEnv)
    if not chunk and err then
        ERROR("BuildChunk failed, err: %s", err)
        return nil
    end
    
    -- DEBUG("---------- BUILD CHUNK ----------", chunk())
    
    local succ, ck = pcall(function() return chunk() end)
    if not succ then
        ERROR("BuildChunk failed")
        return nil
    end

    if ck and not isNotRetFlag then
        return ck
    elseif isNotRetFlag then
        return true
    else
        return nil
    end
end

function HotFix:Clear()
    HotFix.newObjectMap = nil
    HotFix.tableMark = nil
    HotFix.requireMap = nil
    HotFix.reloadMap = nil
    HotFix.fakeEnv = nil
    HotFix.fixUpvalueMap = nil
    HotFix.funcMark = nil
end

function HotFix:Reset()
    HotFix.newObjectMap = {}
    HotFix.tableMark = {}
    HotFix.requireMap = {}
    HotFix.reloadMap = {}
    HotFix.fixUpvalueMap = {}
    HotFix.funcMark = {}
end

return HotFix