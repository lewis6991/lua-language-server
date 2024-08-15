local fw = require('bee.filewatch')
local fs = require('bee.filesystem')
local plat = require('bee.platform')
local await = require('await')
local files = require('files')

local MODIFY = 1 << 0
local RENAME = 1 << 1

local function isExists(filename)
  local path = fs.path(filename)
  local suc, exists = pcall(fs.exists, path)
  if not suc or not exists then
    return false
  end
  if plat.os ~= 'windows' then
    return true
  end
  local res = fs.fullpath(path)
  if not res then
    return false
  end
  if res:string():gsub('^%w+:', string.lower) ~= path:string():gsub('^%w+:', string.lower) then
    return false
  end
  return true
end

--- @class filewatch
local M = {}

M._eventList = {}
M._watchings = {}

--- @async
--- @param path string
--- @param recursive boolean
--- @param filter? fun(path: string):boolean
function M.watch(path, recursive, filter)
  if path == '' or not fs.is_directory(fs.path(path)) then
    return function() end
  end
  if M._watchings[path] then
    M._watchings[path].count = M._watchings[path].count + 1
  else
    local watch = fw.create()
    if recursive then
      watch:set_recursive(true)
      watch:set_follow_symlinks(true)
      watch:set_filter(filter)
    end
    log.debug('Watch add:', path)
    watch:add(path)
    M._watchings[path] = {
      count = 1,
      watch = watch,
    }
    log.debug('fw.add', path)
  end
  local removed
  return function()
    if removed then
      return
    end
    removed = true
    M._watchings[path].count = M._watchings[path].count - 1
    if M._watchings[path].count == 0 then
      M._watchings[path] = nil
      log.debug('fw.remove', path)
    end
  end
end

--- @param callback async fun(ev: string, path: string)
function M.event(callback)
  M._eventList[#M._eventList + 1] = callback
end

function M._callEvent(ev, path)
  for _, callback in ipairs(M._eventList) do
    await.call(function()
      callback(ev, path)
    end)
  end
end

function M.update()
  local collect
  for _, watching in pairs(M._watchings) do
    local watch = watching.watch
    for _ = 1, 10000 do
      local ev, path = watch:select()
      if not ev then
        break
      end
      path = files.normalize(path)
      log.debug('filewatch:', ev, path)
      if not collect then
        collect = {}
      end
      if ev == 'modify' then
        collect[path] = (collect[path] or 0) | MODIFY
      elseif ev == 'rename' then
        collect[path] = (collect[path] or 0) | RENAME
      end
    end
  end

  if not collect or not next(collect) then
    return
  end

  for path, flag in pairs(collect) do
    if flag & RENAME ~= 0 then
      if isExists(path) then
        M._callEvent('create', path)
      else
        M._callEvent('delete', path)
      end
    elseif flag & MODIFY ~= 0 then
      M._callEvent('change', path)
    end
  end
end

return M
