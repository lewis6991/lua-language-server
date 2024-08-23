local timer = require('timer')

local wkmt = { __mode = 'k' }

--- @class await
local M = {}
M.type = 'await'

M.coMap = setmetatable({}, wkmt)
M.idMap = {}
M.delayQueue = {}
M.delayQueueIndex = 1
M.needClose = {}
M._enable = true

local function setID(id, co, callback)
    if not coroutine.isyieldable(co) then
        return
    end
    if not M.idMap[id] then
        M.idMap[id] = setmetatable({}, wkmt)
    end
    M.idMap[id][co] = callback or true
end

--- @param errHandle function When an error occurs, the function f will be called with the error stack as a parameter.
function M.setErrorHandle(errHandle)
    M.errorHandle = errHandle
end

function M.checkResult(co, ...)
    local suc, err = ...
    if not suc and M.errorHandle then
        M.errorHandle(debug.traceback(co, err))
    end
    return ...
end

--- @param callback async fun()
function M.call(callback, ...)
    local co = coroutine.create(callback)
    local closers = {}
    M.coMap[co] = {
        closers = closers,
        priority = false,
    }
    for i = 1, select('#', ...) do
        local id = select(i, ...)
        if not id then
            break
        end
        setID(id, co)
    end

    local currentCo = coroutine.running()
    local current = M.coMap[currentCo]
    if current then
        for closer in pairs(current.closers) do
            closers[closer] = true
            closer(co)
        end
    end
    return M.checkResult(co, coroutine.resume(co))
end

--- Create a task and suspend the current thread.
--- When the task is completed, continue the current thread/if the task is closed,
--- @async
function M.await(callback, ...)
    if not coroutine.isyieldable() then
        return callback(...)
    end
    return M.wait(function(resume, ...)
        M.call(function()
            local returnNil <close> = resume
            resume(callback())
        end, ...)
    end, ...)
end

---Set an id for batch closing tasks
function M.setID(id, callback)
    local co = coroutine.running()
    setID(id, co, callback)
end

--- Close tasks in batches based on ID
function M.close(id)
    local map = M.idMap[id]
    if not map then
        return
    end
    M.idMap[id] = nil
    for co, callback in pairs(map) do
        if coroutine.status(co) == 'suspended' then
            map[co] = nil
            if type(callback) == 'function' then
                xpcall(callback, log.error)
            end
            coroutine.close(co)
        end
    end
end

function M.hasID(id, co)
    co = co or coroutine.running()
    return M.idMap[id] and M.idMap[id][co] ~= nil
end

function M.unique(id, callback)
    M.close(id)
    M.setID(id, callback)
end

--- Sleep for a while
--- @param time number
--- @async
function M.sleep(time)
    if not coroutine.isyieldable() then
        if M.errorHandle then
            M.errorHandle(debug.traceback('Cannot yield'))
        end
        return
    end
    local co = coroutine.running()
    timer.wait(time, function()
        if coroutine.status(co) ~= 'suspended' then
            return
        end
        return M.checkResult(co, coroutine.resume(co))
    end)
    return coroutine.yield()
end

--- Wait until wake up
--- @param callback function
--- @async
function M.wait(callback, ...)
    local co = coroutine.running()
    local resumed
    callback(function(...)
        if resumed then
            return
        end
        resumed = true
        if coroutine.status(co) ~= 'suspended' then
            return
        end
        return M.checkResult(co, coroutine.resume(co, ...))
    end, ...)
    return coroutine.yield()
end

--- @async
function M.delay()
    if not M._enable then
        return
    end
    if not coroutine.isyieldable() then
        return
    end
    local co = coroutine.running()
    local current = M.coMap[co]
    -- TODO
    if current.priority then
        return
    end
    M.delayQueue[#M.delayQueue + 1] = function()
        if coroutine.status(co) ~= 'suspended' then
            return
        end
        return M.checkResult(co, coroutine.resume(co))
    end
    return coroutine.yield()
end

local throttledDelayer = {}
throttledDelayer.__index = throttledDelayer

--- @async
function throttledDelayer:delay()
    if not M._enable then
        return
    end
    self.calls = self.calls + 1
    if self.calls == self.factor then
        self.calls = 0
        return M.delay()
    end
end

function M.newThrottledDelayer(factor)
    return setmetatable({
        factor = factor,
        calls = 0,
    }, throttledDelayer)
end

--- stop then close
--- @async
function M.stop()
    if not coroutine.isyieldable() then
        return
    end
    M.needClose[#M.needClose + 1] = coroutine.running()
    coroutine.yield()
end

local function warnStepTime(passed, waker)
    if passed < 2 then
        log.warn(('Await step takes [%.3f] sec.'):format(passed))
        return
    end
    for i = 1, 100 do
        local name, v = debug.getupvalue(waker, i)
        if not name then
            return
        end
        if name == 'co' then
            log.warn(debug.traceback(v, ('[fire]Await step takes [%.3f] sec.'):format(passed)))
            return
        end
    end
end

function M.step()
    for i = #M.needClose, 1, -1 do
        coroutine.close(M.needClose[i])
        M.needClose[i] = nil
    end

    local resume = M.delayQueue[M.delayQueueIndex]
    if resume then
        M.delayQueue[M.delayQueueIndex] = false
        M.delayQueueIndex = M.delayQueueIndex + 1
        local clock = os.clock()
        resume()
        local passed = os.clock() - clock
        if passed > 0.5 then
            warnStepTime(passed, resume)
        end
        return true
    else
        for i = 1, #M.delayQueue do
            M.delayQueue[i] = nil
        end
        M.delayQueueIndex = 1
        return false
    end
end

function M.setPriority()
    M.coMap[coroutine.running()].priority = true
end

function M.enable()
    M._enable = true
end

function M.disable()
    M._enable = false
end

return M
