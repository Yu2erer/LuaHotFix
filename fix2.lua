
function fix2()
    print("global fix2")
end

-- 测试被 require 能否正常热更
function globalTb:fix2()
    print("globalTb fix2")
end