local thread = require('bee.thread')

local taskPad = thread.channel('taskpad')
local waiter = thread.channel('waiter')

--- @class pub_brave
local M = {}
M.type = 'brave'
M.ability = {}
M.queue = {}

---Register to become a brave person
function M.register(id, privatePad)
  M.id = id

  if #M.queue > 0 then
    for _, info in ipairs(M.queue) do
      waiter:push(M.id, info.name, info.params)
    end
  end
  M.queue = nil

  M.start(privatePad)
end

--- Registration ability
function M.on(name, callback)
  M.ability[name] = callback
end

--- Report
function M.push(name, params)
  if M.id then
    waiter:push(M.id, name, params)
  else
    M.queue[#M.queue + 1] = {
      name = name,
      params = params,
    }
  end
end

--- Start looking for a job
function M.start(privatePad)
  local reqPad = privatePad and thread.channel('req:' .. privatePad) or taskPad
  local resPad = privatePad and thread.channel('res:' .. privatePad) or waiter
  M.push('mem', collectgarbage('count'))
  while true do
    local name, id, params = reqPad:bpop()
    local ability = M.ability[name]
    -- TODO
    if not ability then
      resPad:push(M.id, id)
      log.error('Brave can not handle this work: ' .. name)
    else
      local ok, res = xpcall(ability, log.error, params)
      if ok then
        resPad:push(M.id, id, res)
      else
        resPad:push(M.id, id)
      end
      M.push('mem', collectgarbage('count'))
    end
  end
end

return M
