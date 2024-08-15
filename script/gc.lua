local util = require('utility')

--- @class gc
--- @field package _list table
local mt = {}
mt.__index = mt
mt.type = 'gc'
mt._removed = false

--- @package
mt._max = 10

local function destroyGCObject(obj)
  local tp = type(obj)
  if tp == 'function' then
    xpcall(obj, log.error)
  elseif tp == 'table' then
    local remove = obj.remove
    if type(remove) == 'function' then
      xpcall(remove, log.error, obj)
    end
  end
end

local function isRemoved(obj)
  local tp = type(obj)
  if tp == 'function' then
    for i = 1, 1000 do
      local n, v = debug.getupvalue(obj, i)
      if not n then
        if i > 1 then
          log.warn('Functional destructor has no removed upper value!', util.dump(debug.getinfo(obj)))
        end
        break
      end
      if n == 'removed' then
        if v then
          return true
        end
        break
      end
    end
  elseif tp == 'table' then
    if obj._removed then
      return true
    end
  end
  return false
end

local function zip(self)
  local list = self._list
  local index = 1
  for _ = 1, #list do
    local obj = list[index]
    if not obj then
      break
    end
    if isRemoved(obj) then
      if index == #list then
        list[#list] = nil
        break
      end
      list[index] = list[#list]
    else
      index = index + 1
    end
  end
  self._max = #list * 1.5
  if self._max < 10 then
    self._max = 10
  end
end

function mt:remove()
  if self._removed then
    return
  end
  self._removed = true
  local list = self._list
  for i = 1, #list do
    destroyGCObject(list[i])
  end
end

--- Flag `obj` is automatically removed when the buff is removed.
--- If `obj` is a `function`, --- call it directly; if `obj` is a `table`, call the internal `remove` method.
--- Other situations will not be processed.
--- @param obj any
--- @return any
function mt:add(obj)
  if self._removed then
    destroyGCObject(obj)
    return nil
  end
  self._list[#self._list + 1] = obj
  if #self._list > self._max then
    zip(self)
  end
  return obj
end

--- Create a gc container and use `gc:add(obj)` to put the destructor into the gc container.
---
--- When the gc container is destroyed, the internal destructor will be called (the calling order is not guaranteed)
---
--- The destructor must be in one of the following formats:
--- 1. For an object, use the `obj:remove()` method to destroy it, and use the `obj._removed` attribute to mark it as being destroyed.
--- 2. A destructor, using the upper value `removed` to mark it as being destructed.
---
--- ```lua
--- local gc = ac.gc() -- Create a gc container
--- gc:add(obj1)       -- Put obj1 into the gc container
--- gc:add(obj2)       -- Put obj2 into the gc container
--- gc:remove()        -- Remove the gc container and also remove obj1 and obj2
--- ```
return function()
  return setmetatable({
    _list = {},
  }, mt)
end
