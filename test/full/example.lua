local util = require('utility')
local files = require('files')
local diag = require('core.diagnostics')
local config = require('config')
local fs = require('bee.filesystem')
local luadoc = require('parser').luadoc

-- temporary
---@diagnostic disable: await-in-sync
local function testIfExit(path)
    config.set(nil, 'Lua.workspace.preloadFileSize', 1000000000)
    local buf = util.loadFile(path:string())
    if buf then
        local state

        local clock = os.clock()
        local max = 1
        local need
        local compileClock = 0
        local luadocClock = 0
        local noderClock = 0
        local total
        for i = 1, max do
            ---@type table
            state = TEST(buf)
            local luadocStart = os.clock()
            luadoc(state)
            local luadocPassed = os.clock() - luadocStart
            local passed = os.clock() - clock
            local noderStart = os.clock()
            local noderPassed = os.clock() - noderStart
            compileClock = compileClock + state.compileClock
            luadocClock = luadocClock + luadocPassed
            noderClock = noderClock + noderPassed
            if passed >= 1.0 or i == max then
                need = passed / i
                total = i
                break
            end
        end
        print(
            ('Benchmark compilation test [%s] single time consumption: %.10f (parsing: %.10f, LuaDoc: %.10f, Noder: %.10f)'):format(
                path:filename():string(),
                need,
                compileClock / total,
                luadocClock / total,
                noderClock / total
            )
        )

        local clock = os.clock()
        local max = 100
        local need
        for i = 1, max do
            files.open(TESTURI)
            files.setText(TESTURI, buf)
            diag(TESTURI, false, function() end)
            local passed = os.clock() - clock
            if passed >= 1.0 or i == max then
                need = passed / i
                break
            end
            files.remove(TESTURI)
        end
        print(
            ('Benchmark diagnostic test [%s] single time consumption: %.10f'):format(
                path:filename():string(),
                need
            )
        )
    end
end

testIfExit(ROOT / 'test' / 'example' / 'vm.txt')
testIfExit(ROOT / 'test' / 'example' / 'largeGlobal.txt')
testIfExit(ROOT / 'test' / 'example' / 'guide.txt')
testIfExit(ROOT / 'test' / 'example' / 'jass-common.txt')
testIfExit(fs.path([[D:\github\test\ECObject.lua]]))
