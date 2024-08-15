local thread = require('bee.thread')
local utility = require('utility')
local await = require('await')

thread.newchannel('taskpad')
thread.newchannel('waiter')

local errLog = thread.channel('errlog')
local taskPad = thread.channel('taskpad')
local waiter = thread.channel('waiter')
local type = type
local counter = utility.counter()

local braveTemplate = [[
package.path  = %q
package.cpath = %q
DEVELOP = %s
DBGPORT = %d
DBGWAIT = %s

collectgarbage 'generational'

log = require 'brave.log'

xpcall(dofile, log.error, %q)
local brave = require 'brave'
brave.register(%d, %q)
]]

--- @class pub
local M = {
  type = 'pub',
  braves = {},
  ability = {},
  taskQueue = {},
  taskMap = {},
  prvtPad = {},
}

--- Function of registering a tavern
function M.on(name, callback)
  M.ability[name] = callback
end

--- Recruit brave men. The brave men will receive tasks from the bulletin board. After completing the tasks, they will deliver the tasks to the poster girl.
--- @param num integer
--- @param privatePad string?
function M.recruitBraves(num, privatePad)
  for _ = 1, num do
    local id = #M.braves + 1
    log.debug('Create brave:', id)
    M.braves[id] = {
      id = id,
      thread = thread.thread(
        braveTemplate:format(
          package.path,
          package.cpath,
          DEVELOP,
          DBGPORT or 11412,
          DBGWAIT or 'nil',
          (ROOT / 'debugger.lua'):string(),
          id,
          privatePad
        )
      ),
      taskMap = {},
      currentTask = nil,
      memory = 0,
    }
  end
  if privatePad and not M.prvtPad[privatePad] then
    thread.newchannel('req:' .. privatePad)
    thread.newchannel('res:' .. privatePad)
    M.prvtPad[privatePad] = {
      req = thread.channel('req:' .. privatePad),
      res = thread.channel('res:' .. privatePad),
    }
  end
end

--- Push tasks to brave men
function M.pushTask(info)
  if info.removed then
    return false
  end
  if M.prvtPad[info.name] then
    M.prvtPad[info.name].req:push(info.name, info.id, info.params)
  else
    taskPad:push(info.name, info.id, info.params)
  end
  M.taskMap[info.id] = info
  return true
end

--- Receive mission feedback from the brave
function M.popTask(brave, id, result)
  local info = M.taskMap[id]
  if not info then
    log.warn(('Brave pushed unknown task result: # %d => [%d]'):format(brave.id, id))
    return
  end
  M.taskMap[id] = nil
  if not info.removed then
    info.removed = true
    if info.callback then
      xpcall(info.callback, log.error, result)
    end
  end
end

--- Receive reports from heroes
function M.popReport(brave, name, params)
  local abil = M.ability[name]
  if not abil then
    log.warn(('Brave pushed unknown report: # %d => %q'):format(brave.id, name))
    return
  end
  xpcall(abil, log.error, params, brave)
end

--- Release tasks
--- @param name string
--- @param params any
--- @return any
--- @async
function M.awaitTask(name, params)
  local info = {
    id = counter(),
    name = name,
    params = params,
  }
  if M.pushTask(info) then
    return await.wait(function(waker)
      info.callback = waker
    end)
  else
    return false
  end
end

--- Publish a synchronization task. If the task enters the queue, it will return to the executor.
--- Queue can be jumped through jumpQueue
--- @param name string
--- @param params any
--- @param callback? function
function M.task(name, params, callback)
  local info = {
    id = counter(),
    name = name,
    params = params,
    callback = callback,
  }
  return M.pushTask(info)
end

function M.reciveFromPad(pad)
  local suc, id, name, result = pad:pop()
  if not suc then
    return false
  end
  if type(name) == 'string' then
    M.popReport(M.braves[id], name, result)
  else
    M.popTask(M.braves[id], name, result)
  end
  return true
end

---Receive feedback
function M.recieve(block)
  if block then
    local id, name, result = waiter:bpop()
    if type(name) == 'string' then
      M.popReport(M.braves[id], name, result)
    else
      M.popTask(M.braves[id], name, result)
    end
  else
    while true do
      local ok
      if M.reciveFromPad(waiter) then
        ok = true
      end
      for _, pad in pairs(M.prvtPad) do
        if M.reciveFromPad(pad.res) then
          ok = true
        end
      end

      if not ok then
        break
      end
    end
  end
end

--- Check the casualties
function M.checkDead()
  while true do
    local suc, err = errLog:pop()
    if not suc then
      break
    end
    log.error('Brave is dead!: ' .. err)
  end
end

function M.step(block)
  M.checkDead()
  M.recieve(block)
end

return M
