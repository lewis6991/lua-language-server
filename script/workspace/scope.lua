local gc = require('gc')

--- @class scope.manager
local M = {}

--- @alias scope.type '"override"'|'"folder"'|'"fallback"'

--- @class scope
--- @field type   scope.type
--- @field uri?   string
--- @field _links table<string, boolean>
--- @field _data  table<string, any>
--- @field _gc    gc
--- @field _removed? true
local mt = {}
mt.__index = mt

function mt:__tostring()
  if self.uri then
    return ('{scope|%s|%s}'):format(self.type, self.uri)
  else
    return ('{scope|%s}'):format(self.type)
  end
end

--- @param uri string
function mt:addLink(uri)
  self._links[uri] = true
end

--- @param uri string
function mt:removeLink(uri)
  self._links[uri] = nil
end

function mt:removeAllLinks()
  self._links = {}
end

--- @return fun(): string
--- @return table<string, true>
function mt:eachLink()
  return next, self._links
end

--- @param uri string
--- @return boolean
function mt:isChildUri(uri)
  if not uri then
    return false
  end
  if not self.uri then
    return false
  end
  if self.uri == uri then
    return true
  end
  if uri:sub(1, #self.uri) ~= self.uri then
    return false
  end
  if uri:sub(#self.uri, #self.uri) == '/' or uri:sub(#self.uri + 1, #self.uri + 1) == '/' then
    return true
  end
  return false
end

--- @param uri string
--- @return boolean
function mt:isLinkedUri(uri)
  if not uri then
    return false
  end
  for linkUri in pairs(self._links) do
    if uri == linkUri then
      return true
    end
    if uri:sub(1, #linkUri) ~= linkUri then
      goto CONTINUE
    end
    if uri:sub(#linkUri, #linkUri) == '/' or uri:sub(#linkUri + 1, #linkUri + 1) == '/' then
      return true
    end
    ::CONTINUE::
  end
  return false
end

--- @param uri string
--- @return boolean
function mt:isVisible(uri)
  return self:isChildUri(uri) or self:isLinkedUri(uri) or self == M.getScope(uri)
end

--- @param uri string
--- @return string?
function mt:getLinkedUri(uri)
  if not uri then
    return nil
  end
  for linkUri in pairs(self._links) do
    if uri:sub(1, #linkUri) == linkUri then
      return linkUri
    end
  end
  return nil
end

--- @param uri string
--- @return string?
function mt:getRootUri(uri)
  if self:isChildUri(uri) then
    return self.uri
  end
  return self:getLinkedUri(uri)
end

--- @param k string
--- @param v any
function mt:set(k, v)
  self._data[k] = v
  return v
end

function mt:get(k)
  return self._data[k]
end

--- @return string
function mt:getName()
  return self.uri or ('<' .. self.type .. '>')
end

function mt:gc(obj)
  self._gc:add(obj)
end

function mt:flushGC()
  self._gc:remove()
  if self._removed then
    return
  end
  self._gc = gc()
end

function mt:remove()
  if self._removed then
    return
  end
  self._removed = true
  for i, scp in ipairs(M.folders) do
    if scp == self then
      table.remove(M.folders, i)
      break
    end
  end
  self:flushGC()
end

function mt:isRemoved()
  return self._removed == true
end

--- @param scopeType scope.type
--- @return scope
local function createScope(scopeType)
  local scope = setmetatable({
    type = scopeType,
    _links = {},
    _data = {},
    _gc = gc(),
  }, mt)

  return scope
end

function M.reset()
  ---@type scope[]
  M.folders = {}
  M.override = createScope('override')
  M.fallback = createScope('fallback')
end

M.reset()

--- @param uri string
--- @return scope
function M.createFolder(uri)
  local scope = createScope('folder')
  scope.uri = uri

  local inserted = false
  for i, otherScope in ipairs(M.folders) do
    if #uri > #otherScope.uri then
      table.insert(M.folders, i, scope)
      inserted = true
      break
    end
  end
  if not inserted then
    table.insert(M.folders, scope)
  end

  return scope
end

--- @param uri string
--- @return scope?
function M.getFolder(uri)
  for _, scope in ipairs(M.folders) do
    if scope:isChildUri(uri) then
      return scope
    end
  end
  return nil
end

--- @param uri string
--- @return scope?
function M.getLinkedScope(uri)
  if M.override and M.override:isLinkedUri(uri) then
    return M.override
  end
  for _, scope in ipairs(M.folders) do
    if scope:isLinkedUri(uri) then
      return scope
    end
  end
  if M.fallback:isLinkedUri(uri) then
    return M.fallback
  end
  return nil
end

--- @param uri? string
--- @return scope
function M.getScope(uri)
  return uri and (M.getFolder(uri) or M.getLinkedScope(uri)) or M.fallback
end

return M
