local guide = require('parser.guide')

local LocalLimit = 200

--- @class parser.Chunk
local M = {}

M.localCount = 0

local chunks = {} --- @type parser.object.block[]

local pushError

function M.push(chunk)
  chunks[#chunks + 1] = chunk
end

---@param x parser.object.union
function M.pushIntoCurrent(x)
  local chunk = chunks[#chunks]
  if chunk then
    chunk[#chunk + 1] = x
    x.parent = chunk
  end
end

function M.get()
  return chunks[#chunks]
end

--- @param label parser.object.label
--- @param obj parser.object.goto
local function resolveLabel(label, obj)
  label.ref = label.ref or {}
  label.ref[#label.ref + 1] = obj
  obj.node = label

  -- If there is a local variable declared between goto and label,
  -- and used after label, it is counted as a syntax error

  -- If label is declared before goto, there will be no local variables declared in the middle
  if obj.start > label.start then
    return
  end

  local block = guide.getBlock(obj)
  local locals = block and block.locals

  for _, loc in ipairs(locals or {}) do
    local should_break = (function()
      -- Check that the local variable declaration position is between goto and label
      if loc.start < obj.start or loc.finish > label.finish then
        return
      end
      -- Check where local variables are used after label
      local refs = loc.ref
      if not refs then
        return
      end
      for j = 1, #refs do
        local ref = refs[j]
        if ref.finish > label.finish then
          pushError({
            type = 'JUMP_LOCAL_SCOPE',
            at = obj,
            info = {
              loc = loc[1],
            },
            relative = {
              {
                start = label.start,
                finish = label.finish,
              },
              {
                start = loc.start,
                finish = loc.finish,
              },
            },
          })
          return true
        end
      end
    end)()

    if should_break then
      break
    end
  end
end

--- @param gotos parser.object.block[]
local function resolveGoTo(gotos)
  for i = 1, #gotos do
    local action = gotos[i]
    local label = guide.getLabel(action, action[1])
    if label then
      resolveLabel(label, action)
    else
      pushError({
        type = 'NO_VISIBLE_LABEL',
        at = action,
        info = {
          label = action[1],
        },
      })
    end
  end
end

function M.pop()
  local chunk = chunks[#chunks]
  if chunk.gotos then
    resolveGoTo(chunk.gotos)
    chunk.gotos = nil
  end
  local lastAction = chunk[#chunk]
  if lastAction then
    chunk.finish = lastAction.finish
  end
  chunks[#chunks] = nil
end

function M.drop()
  chunks[#chunks] = nil
end

function M.clear()
  for i = 1, #chunks do
    chunks[i] = nil
  end
end

--- @param x parser.object.local
function M.addLocal(x)
  -- Add local to current chunk
  local chunk = chunks[#chunks]
  if chunk then
    chunk.locals = chunk.locals or {}
    local locals = chunk.locals
    locals[#locals + 1] = x
    M.localCount = M.localCount + 1
    if not LocalLimited and M.localCount > LocalLimit then
      LocalLimited = true
      pushError({ type = 'LOCAL_LIMIT', at = x })
    end
  end
end

function M.iter_rev()
  local i = #chunks + 1
  return function()
    i = i - 1
    return chunks[i]
  end
end

return function(pushErrorArg)
  pushError = pushErrorArg
  M.localCount = 0
  M.clear()
  return M
end
