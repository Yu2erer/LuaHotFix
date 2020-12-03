
-- 测试 global table 热更
globalTb = {}

-- 模拟 require 一个子文件的热更
require("fix2")


-- 测试 local function 热更
local function localFn()
    print("localFn")
end

function localFnHelper()
    localFn()
end

-- 测试 global function 热更
function globalFn()
    print("globalFn")
end

-- 测试 global table 函数 热更
function globalTb:test()
    print("globalTb test")
end


-- 测试 global table 函数 含 upvalue 热更
local i = 0
function globalTb:test2()
    i = i + 1
    print(i)
end

-- 测试热更能否根据全局变量进行不同操作
function IsGameSvr()
    if ISGAMESVR then
        print("is game svr")
    else
        print("not a game svr")
    end
end

-- 测试热更修改数据
-- globalTb.a = 1000
function changeA()
    if globalTb.a then
        print("changeA", globalTb.a)
    end
end

-- 热更的时候 启用 会自动执行本函数，进行数据修复
-- function __RELOAD()
--     globalTb.a = 1000000
-- end