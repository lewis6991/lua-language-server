local util = require('utility')
local await = require('await')
local pub = require('pub')
local jsonrpc = require('jsonrpc')
local define = require('proto.define')
local json = require('json')
local inspect = require('inspect')
local platform = require('bee.platform')
local fs = require('bee.filesystem')
local net = require('service.net')
local timer      = require 'timer'

local reqCounter = util.counter()

local function logSend(buf)
    if not RPCLOG then
        return
    end
    log.info('rpc send:', buf)
end

local function logRecieve(proto)
    if not RPCLOG then
        return
    end
    log.info('rpc recieve:', json.encode(proto))
end

--- @class proto
local M = {
    ability = {},
    waiting = {},
    holdon = {},
    mode = 'stdio',
    client = nil,
}

function M.getMethodName(proto)
    if proto.method:sub(1, 2) == '$/' then
        return proto.method, true
    else
        return proto.method, false
    end
end

--- @param callback async fun()
function M.on(method, callback)
    M.ability[method] = callback
end

function M.send(data)
    local buf = jsonrpc.encode(data)
    logSend(buf)
    if M.mode == 'stdio' then
        io.write(buf)
    elseif M.mode == 'socket' then
        M.client:write(buf)
    end
end

function M.response(id, res)
    if id == nil then
        log.error('Response id is nil!', inspect(res))
        return
    end
    if not M.holdon[id] then
        log.error('Unknown response id!', id)
        return
    end
    M.holdon[id] = nil
    local data = {}
    data.id = id
    data.result = res == nil and json.null or res
    M.send(data)
end

function M.responseErr(id, code, message)
    if id == nil then
        log.error('Response id is nil!', inspect(message))
        return
    end
    if not M.holdon[id] then
        log.error('Unknown response id!', id)
        return
    end
    M.holdon[id] = nil
    M.send({
        id = id,
        error = {
            code = code,
            message = message,
        },
    })
end

function M.notify(name, params)
    M.send({
        method = name,
        params = params,
    })
end

--- @async
function M.awaitRequest(name, params)
    local id = reqCounter()
    M.send({
        id = id,
        method = name,
        params = params,
    })
    local result, error = await.wait(function(resume)
        M.waiting[id] = {
            id = id,
            method = name,
            params = params,
            resume = resume,
        }
    end)
    if error then
        log.warn(('Response of [%s] error [%d]: %s'):format(name, error.code, error.message))
    end
    return result
end

function M.request(name, params, callback)
    local id = reqCounter()
    M.send({
        id = id,
        method = name,
        params = params,
    })
    M.waiting[id] = {
        id = id,
        method = name,
        params = params,
        resume = function(result, error)
            if error then
                log.warn(
                    ('Response of [%s] error [%d]: %s'):format(name, error.code, error.message)
                )
            end
            if callback then
                callback(result)
            end
        end,
    }
end

local secretOption = {
    process = function(item, path)
        if
            path[1] == 'params'
            and path[2] == 'textDocument'
            and path[3] == 'text'
            and path[4] == nil
        then
            return '"***"'
        end
        return item
    end,
}

M.methodQueue = {}

function M.applyMethod(proto)
    logRecieve(proto)
    local method, optional = M.getMethodName(proto)
    local abil = M.ability[method]
    if proto.id then
        M.holdon[proto.id] = proto
    end
    if not abil then
        if not optional then
            log.warn('Recieved unknown proto: ' .. method)
        end
        if proto.id then
            M.responseErr(proto.id, define.ErrorCodes.MethodNotFound, method)
        end
        return
    end
    await.call(function() ---@async
        --log.debug('Start method:', method)
        if proto.id then
            await.setID('proto:' .. proto.id)
        end
        local clock = os.clock()
        local ok = false
        local res
        -- The task may be interrupted during execution and captured by close
        local response <close> = function()
            local passed = os.clock() - clock
            if passed > 0.5 then
                log.warn(
                    ('Method [%s] takes [%.3f]sec. %s'):format(
                        method,
                        passed,
                        inspect(proto, secretOption)
                    )
                )
            end
            --log.debug('Finish method:', method)
            if not proto.id then
                return
            end
            await.close('proto:' .. proto.id)
            if ok then
                M.response(proto.id, res)
            else
                M.responseErr(
                    proto.id,
                    proto._closeReason or define.ErrorCodes.InternalError,
                    proto._closeMessage or res
                )
            end
        end
        ok, res = xpcall(abil, log.error, proto.params, proto.id)
        await.delay()
    end)
end

function M.applyMethodQueue()
    local queue = M.methodQueue
    M.methodQueue = {}
    local canceled = {}
    for _, proto in ipairs(queue) do
        if proto.method == '$/cancelRequest' then
            canceled[proto.params.id] = true
        end
    end
    for _, proto in ipairs(queue) do
        if not canceled[proto.id] then
            M.applyMethod(proto)
        end
    end
end

function M.doMethod(proto)
    M.methodQueue[#M.methodQueue+1] = proto
    if #M.methodQueue > 1 then
        return
    end
    timer.wait(0, M.applyMethodQueue)
end

function M.close(id, reason, message)
    local proto = M.holdon[id]
    if not proto then
        return
    end
    proto._closeReason = reason
    proto._closeMessage = message
    await.close('proto:' .. id)
end

function M.doResponse(proto)
    logRecieve(proto)
    local id = proto.id
    local waiting = M.waiting[id]
    if not waiting then
        log.warn('Response id not found: ' .. inspect(proto))
        return
    end
    M.waiting[id] = nil
    if proto.error then
        waiting.resume(nil, proto.error)
        return
    end
    waiting.resume(proto.result)
end

function M.listen(mode, socketPort)
    M.mode = mode
    if mode == 'stdio' then
        log.info('Listen Mode: stdio')
        if platform.os == 'windows' then
            local windows = require('bee.windows')
            windows.filemode(io.stdin, 'b')
            windows.filemode(io.stdout, 'b')
        end
        io.stdin:setvbuf('no')
        io.stdout:setvbuf('no')
        pub.task('loadProtoByStdio')
    elseif mode == 'socket' then
        local unixFolder = LOGPATH .. '/unix'
        fs.create_directories(fs.path(unixFolder))
        local unixPath = unixFolder .. '/' .. tostring(socketPort)

        local server = net.listen('unix', unixPath)

        log.info('Listen Mode: socket')
        log.info('Listen Port:', socketPort)
        log.info('Listen Path:', unixPath)

        assert(server)

        local dummyClient = {
            buf = '',
            write = function(self, data)
                self.buf = self.buf .. data
            end,
            update = function() end,
        }
        M.client = dummyClient

        function server:on_accepted(client)
            M.client = client
            client:write(dummyClient.buf)
            return true
        end

        function server:on_error(...)
            log.error(...)
        end

        pub.task('loadProtoBySocket', {
            port = socketPort,
            unixPath = unixPath,
        })
    end
end

return M
