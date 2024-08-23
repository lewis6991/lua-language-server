local brave = require('brave')
local time = require('bee.time')

local tablePack = table.pack
local tostring = tostring
local tableConcat = table.concat
local debugTraceBack = debug.traceback
local debugGetInfo = debug.getinfo
local monotonic = time.monotonic

_ENV = nil

local function pushLog(level, ...)
    local t = tablePack(...)
    for i = 1, t.n do
        t[i] = tostring(t[i])
    end
    local str = tableConcat(t, '\t', 1, t.n)
    if level == 'error' then
        str = str .. '\n' .. debugTraceBack(nil, 3)
    end
    local info = debugGetInfo(3, 'Sl')
    brave.push('log', {
        level = level,
        msg = str,
        src = info.source,
        line = info.currentline,
        clock = monotonic(),
    })
    return str
end

local M = {}

function M.info(...)
    pushLog('info', ...)
end

function M.debug(...)
    pushLog('debug', ...)
end

function M.trace(...)
    pushLog('trace', ...)
end

function M.warn(...)
    pushLog('warn', ...)
end

function M.error(...)
    pushLog('error', ...)
end

return M
