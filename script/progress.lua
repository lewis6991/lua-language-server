local proto = require('proto.proto')
local util = require('utility')
local timer = require('timer')
local config = require('config')
local time = require('bee.time')

local nextToken = util.counter()

local M = {}

M.map = {}

--- @class progress
--- @field _uri   string
--- @field _token integer
local mt = {}
mt.__index = mt
mt._title = nil
mt._message = nil
mt._removed = false
mt._clock = 0.0
mt._delay = 0.0
mt._percentage = 0.0
mt._showed = false
mt._dirty = true
mt._updated = 0.0
mt._onCancel = nil

--- Remove progress bar
function mt:remove()
    if self._removed then
        return
    end
    self._removed = true
    local token = self._token
    M.map[token] = nil
    if self._showed then
        self._showed = false
        proto.notify('$/progress', {
            token = token,
            value = {
                kind = 'end',
            },
        })
        --log.info('Remove progress:', token, self._title)
    end
end

function mt:isRemoved()
    return self._removed == true
end

--- Setting description
--- @param message string # Description
function mt:setMessage(message)
    if self._message == message then
        return
    end
    self._message = message
    self._dirty = true
    self:update()
end

--- Set percentage
--- @param per number Percentage (1-100)
function mt:setPercentage(per)
    if self._percentage == per then
        return
    end
    self._percentage = math.floor(per)
    self._dirty = true
    self:update()
end

--- Cancel event
function mt:onCancel(callback)
    self._onCancel = callback
    self:update()
end

function mt:update()
    if self._removed then
        return
    end
    if not self._dirty then
        return
    end
    if not self._showed and self._clock + self._delay <= time.time() then
        self._updated = time.time()
        self._dirty = false
        if not config.get(self._uri, 'Lua.window.progressBar') then
            return
        end
        proto.request('window/workDoneProgress/create', {
            token = self._token,
        })
        proto.notify('$/progress', {
            token = self._token,
            value = {
                kind = 'begin',
                title = self._title,
                cancellable = self._onCancel ~= nil,
                message = self._message,
                percentage = self._percentage,
            },
        })
        self._showed = true
        --log.info('Create progress:', self._token, self._title)
        return
    end
    if not self._showed then
        return
    end
    if not config.get(self._uri, 'Lua.window.progressBar') then
        self:remove()
        return
    end
    if time.time() - self._updated < 50 then
        return
    end
    self._dirty = false
    self._updated = time.time()
    proto.notify('$/progress', {
        token = self._token,
        value = {
            kind = 'report',
            message = self._message,
            percentage = self._percentage,
        },
    })
    --log.info('Report progress:', self._token, self._title, self._message, self._percentage)
end

function mt:__close()
    --log.info('Close progress:', self._token, self._title, self._message)
    self:remove()
end

function M.update()
    ---@param prog progress
    for _, prog in pairs(M.map) do
        if prog:isRemoved() then
            goto CONTINUE
        end
        prog:update()
        ::CONTINUE::
    end
end

--- Create a progress bar
--- @param uri?  string
--- @param title string # Title
--- @param delay number # It will be displayed after at least this long.
function M.create(uri, title, delay)
    local token = nextToken()
    local prog = setmetatable({
        _token = token,
        _title = title,
        _clock = time.time(),
        _delay = delay * 1000,
        _uri = uri,
    }, mt)

    M.map[token] = prog

    return prog
end

--- Cancel a progress bar
function M.cancel(token)
    local prog = M.map[token]
    if not prog then
        return
    end
    xpcall(prog._onCancel, log.error, prog)
    prog:remove()
end

timer.loop(0.1, M.update)

return M
