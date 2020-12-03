function sleep(n)
    local time = os.clock();
    while true do
        if os.clock() - time > n then
            return
        end
    end
end

local HotFix = require("HotFix")
require("fix1")

-- 模拟 根据全局变量 进行热更新
ISGAMESVR = true

-- 模拟 禁止修改环境表 进行热更新
local tb = {
    __newindex = function (tb, k, v)
        error("Attempt create global value :"..tostring(k), 2);
    end,
}
setmetatable(_G, tb)


local i = 0

while true do
    -- 测试 local function 热更
    localFnHelper()
    -- 测试 global function 热更
    globalFn()
    -- 测试 global table 函数 热更
    globalTb:test()
    -- 测试 global table 函数 含 upvalue 热更
    globalTb:test2()
    -- 测试热更能否根据全局变量进行不同操作
    IsGameSvr()
    -- 测试被 require 能否正常热更
    globalTb:fix2()
    fix2()
    -- 测试热更修改数据
    changeA()
    
    -- 休眠2秒，给你时间去改代码...
    sleep(2)
    -- 开始热更
    HotFix:UpdateModule("fix1")
end
