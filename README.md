# LuaHotFix
Lua 服务端热更新

## 前言

游戏服务端之所以用 Lua，大多数时候是因为 Lua 方便做热更新，一般来说对 Lua 做热更新基本上都会使用以下两句语句。

```lua
package.loaded[name] = nil
require(name)
```

这种方式的热更好处就是简单，不过有的代码写起来就要特别小心，当你在代码中看到以下类似的片段，很有可能是为了热更新做的一种妥协。

```lua
Activity.c2sFun = Activity.c2sFun or {};
```

同时，如果 Lua 代码中存有大量的 `upvalue` 时，还要记得保存原有的状态信息，否则会丢失原值，对于开发人员来说，这种热更方式费心费力。

因此， `Lua HotFix` 就是为了摆脱以上的限制，让开发人员能够更为简单的做热更新。之所以要自己写这么一套东西，主要是因为网络上开源的热更方案不适合项目。

## HotFix 实现

通过 `loadfile` 将文件读入 Lua ，此时为一个 `function` 也就是 chunk，设置这个 `function` 的执行环境为我的 假环境表 我管它叫 `fakeEnv` ，在里面替换掉一些函数，然后执行 `chunk` ，就能从 `fakeEnv` 得到一系列的函数，全局变量信息。

接下来是确定什么能更新，什么不能更新。首先函数必更新，因为你热更不更逻辑，要你有何用？其次数据默认不更新，为什么是默认不更新，主要考虑到 `upvalue` ，优先保证服务器正常运作（哪怕我热更失败），但是 table 这个类型我们要更新，只更新函数即可，table 中的数据也采用默认不更新的思路。

这个时候就能成功的更新上新的逻辑了，此时就要考虑数据的更新，因为我们不确定什么数据是需要更新的（比如说配置信息），因此默认是不更新数据的，如果需要更新数据，则通过 在模块中加入 `__RELOAD` 函数，因为什么数据要更新，使用者最为清楚，其次使用这个 `__RELOAD` 函数，代码入库也极为方便，直接在文件底部调用即可。

代码片段示例

```lua
yuerer = {}
yuerer.age = 21

function __RELOAD()
	yuerer.age = 22
end

__RELOAD() -- 热更后可直接入库
```


因此，使用这套热更新有以下约束

1. 除了函数会更新，其他默认不更新（table 里面的数据也不会默认更新，因为有的开发人员喜欢在 table 里保存状态数据）
2. 如果要更新除了函数以外的信息，自行定义 __RELOAD 函数，并实现
3. 不支持 userdata，thread 类型 
4. 不要存任何 function，table 的引用（或者是显式在 __RELOAD 函数中重置引用）
5. 不要热更 _ENV 的 metatable


## How to use

1. 假设我们 require 了一个模块 fix1，此时我们要更新 fix1 中的代码。

```Lua
require("fix1")
local HotFix = require("HotFix")
HotFix:UpdateModule("fix1")
```

这样就能实现最基础的 除 `userdata` `thread` 类型的热更新


2. 如果想要更新数据，请在 fix1 模块下 写一个 `__RELOAD` 函数
这主要是基于两个原因
    * 数据可能有状态信息
    * 方便入库

```Lua
function __RELOAD()
    -- do some things
end
```

