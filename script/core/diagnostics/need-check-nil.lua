local files = require('files')
local guide = require('parser.guide')
local vm = require('vm')
local lang = require('language')
local await = require('await')

local function checkNil(src)
  local nxt = src.next
  if nxt then
    if
      nxt.type == 'getfield'
      or nxt.type == 'getmethod'
      or nxt.type == 'getindex'
      or nxt.type == 'call'
    then
      return true
    end
  end

  local parent = src.parent
  if parent then
    if parent.type == 'call' and parent.node == src then
      return true
    end

    if parent.type == 'setindex' and parent.index == src then
      return true
    end
  end

  return false
end

--- @async
return function(uri, callback)
  local state = files.getState(uri)
  if not state then
    return
  end

  local delayer = await.newThrottledDelayer(500)
  ---@async
  guide.eachSourceType(state.ast, 'getlocal', function(src)
    delayer:delay()
    if not checkNil(src) then
      return
    end

    if not vm.compileNode(src):hasFalsy() then
      return
    end

    if vm.getInfer(src):hasType(uri, 'any') then
      return
    end

    callback({
      start = src.start,
      finish = src.finish,
      message = lang.script('DIAG_NEED_CHECK_NIL'),
    })
  end)
end
