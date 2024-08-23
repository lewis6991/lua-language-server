local guide = require('parser.guide')
local files = require('files')
local timer = require('timer')

local weakMT = { __mode = 'kv' }

--- @class vm
local M = {}

M.ID_SPLITE = '\x1F'

function M.getSpecial(source)
    if source then
        return source.special
    end
end

--- @param source parser.object
--- @return string?
function M.getKeyName(source)
    if not source then
        return nil
    end
    if source.type == 'call' then
        local special = M.getSpecial(source.node)
        if special == 'rawset' or special == 'rawget' then
            return guide.getKeyNameOfLiteral(source.args[2])
        end
    end
    return guide.getKeyName(source)
end

function M.getKeyType(source)
    if not source then
        return nil
    end
    if source.type == 'call' then
        local special = M.getSpecial(source.node)
        if special == 'rawset' or special == 'rawget' then
            return guide.getKeyTypeOfLiteral(source.args[2])
        end
    end
    return guide.getKeyType(source)
end

--- @param source parser.object
--- @return parser.object?
function M.getObjectValue(source)
    if source.value then
        return source.value
    end
    if source.special == 'rawset' then
        return source.args and source.args[3]
    end
    return nil
end

--- @param source parser.object
--- @return parser.object?
function M.getObjectFunctionValue(source)
    local value = M.getObjectValue(source)
    if value == nil then
        return
    elseif value.type == 'function' or value.type == 'doc.type.function' then
        return value
    elseif value.type == 'getlocal' then
        return M.getObjectFunctionValue(value.node)
    end
    return value
end

M.cacheTracker = setmetatable({}, weakMT)

function M.flushCache()
    if M.cache then
        M.cache.dead = true
    end
    M.cacheVersion = files.globalVersion
    M.cache = {}
    M.cacheActiveTime = math.huge
    M.locked = setmetatable({}, weakMT)
    M.cacheTracker[M.cache] = true
end

function M.getCache(name, weak)
    if M.cacheVersion ~= files.globalVersion then
        M.flushCache()
    end
    M.cacheActiveTime = timer.clock()
    if not M.cache[name] then
        M.cache[name] = weak and setmetatable({}, weakMT) or {}
    end
    return M.cache[name]
end

local function init()
    M.flushCache()

    -- It's possible to clear the cache after a period of inactivity, but it doesn't seem necessary at the moment.
    --timer.loop(1, function ()
    --    if timer.clock() - m.cacheActiveTime > 10.0 then
    --        log.info('Flush cache: Inactive')
    --        m.flushCache()
    --        collectgarbage()
    --    end
    --end)
end

xpcall(init, log.error)

return M
