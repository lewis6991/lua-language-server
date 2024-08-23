local files = require('files')
--- @class vm
local vm = require('vm.vm')
local ws = require('workspace.workspace')
local guide = require('parser.guide')
local timer = require('timer')
local util = require('utility')

--- @type table<vm.object, vm.node>
local nodeCache = setmetatable({}, { __mode = 'k' })

--- @alias vm.node.object vm.object | vm.global | vm.variable

--- @class vm.node
--- @field [integer] vm.node.object
--- @field [vm.node.object] true
--- @field fields? table<vm.node|string, vm.node>
--- @field undefinedGlobal boolean?
--- @field lastInfer? vm.infer
local Node = {
    id = 0,
    type = 'vm.node',
    optional = nil,
    data = nil,
    hasDefined = nil,
    originNode = nil,
}
Node.__index = Node

--- @param node vm.node | vm.node.object
--- @return vm.node
function Node:merge(node)
    if not node then
        return self
    end
    self.lastInfer = nil
    if node.type == 'vm.node' then
        if node == self then
            return self
        end
        if node:isOptional() then
            self.optional = true
        end
        for _, obj in ipairs(node) do
            if not self[obj] then
                self[obj] = true
                self[#self + 1] = obj
            end
        end
    else
        ---@cast node -vm.node
        if not self[node] then
            self[node] = true
            self[#self + 1] = node
        end
    end
    return self
end

--- @return boolean
function Node:isEmpty()
    return #self == 0
end

--- @return boolean
function Node:isTyped()
    for _, c in ipairs(self) do
        if c.type == 'global' and c.cate == 'type' then
            return true
        end
        if guide.isLiteral(c) then
            return true
        end
    end
    return false
end

function Node:clear()
    self.optional = nil
    for i, c in ipairs(self) do
        self[i] = nil
        self[c] = nil
    end
end

--- @param n integer
--- @return vm.node.object?
function Node:get(n)
    return self[n]
end

function Node:addOptional()
    self.optional = true
end

function Node:removeOptional()
    self:remove('nil')
    return self
end

--- @return boolean
function Node:isOptional()
    return self.optional == true
end

--- @return boolean
function Node:hasFalsy()
    if self.optional then
        return true
    end
    for _, c in ipairs(self) do
        if
            c.type == 'nil'
            or (c.type == 'global' and c.cate == 'type' and c.name == 'nil')
            or (c.type == 'global' and c.cate == 'type' and c.name == 'false')
            or (c.type == 'boolean' and c[1] == false)
            or (c.type == 'doc.type.boolean' and c[1] == false)
        then
            return true
        end
    end
    return false
end

--- @return boolean
function Node:hasKnownType()
    for _, c in ipairs(self) do
        if c.type == 'global' and c.cate == 'type' then
            return true
        end
        if guide.isLiteral(c) then
            return true
        end
    end
    return false
end

--- @return boolean
function Node:isNullable()
    if self.optional then
        return true
    end
    if #self == 0 then
        return true
    end
    for _, c in ipairs(self) do
        if
            c.type == 'nil'
            or (c.type == 'global' and c.cate == 'type' and c.name == 'nil')
            or (c.type == 'global' and c.cate == 'type' and c.name == 'any')
            or (c.type == 'global' and c.cate == 'type' and c.name == '...')
        then
            return true
        end
    end
    return false
end

--- @return vm.node
function Node:setTruthy()
    if self.optional == true then
        self.optional = nil
    end
    local hasBoolean
    for index = #self, 1, -1 do
        local c = self[index]
        if
            c.type == 'nil'
            or (c.type == 'global' and c.cate == 'type' and c.name == 'nil')
            or (c.type == 'global' and c.cate == 'type' and c.name == 'false')
            or (c.type == 'boolean' and c[1] == false)
            or (c.type == 'doc.type.boolean' and c[1] == false)
        then
            table.remove(self, index)
            self[c] = nil
        elseif c.type == 'global' and c.cate == 'type' and c.name == 'boolean' then
            hasBoolean = true
            table.remove(self, index)
            self[c] = nil
        elseif c.type == 'boolean' or c.type == 'doc.type.boolean' then
            if c[1] == false then
                table.remove(self, index)
                self[c] = nil
            end
        end
    end
    if hasBoolean then
        self:merge(vm.declareGlobal('type', 'true'))
    end
    return self
end

--- @return vm.node
function Node:setFalsy()
    if self.optional == false then
        self.optional = nil
    end
    local hasBoolean
    for index = #self, 1, -1 do
        local c = self[index]
        if
            c.type == 'nil'
            or (c.type == 'global' and c.cate == 'type' and c.name == 'nil')
            or (c.type == 'global' and c.cate == 'type' and c.name == 'false')
            or (c.type == 'boolean' and c[1] == false)
            or (c.type == 'doc.type.boolean' and c[1] == false)
        then
        -- pass
        elseif c.type == 'global' and c.cate == 'type' and c.name == 'boolean' then
            hasBoolean = true
            table.remove(self, index)
            self[c] = nil
        elseif c.type == 'boolean' or c.type == 'doc.type.boolean' and c[1] == true then
            table.remove(self, index)
            self[c] = nil
        elseif c.type == 'global' and c.cate == 'type' then
            table.remove(self, index)
            self[c] = nil
        elseif guide.isLiteral(c) then
            table.remove(self, index)
            self[c] = nil
        end
    end
    if hasBoolean then
        self:merge(vm.declareGlobal('type', 'false'))
    end
    return self
end

--- @param name string
function Node:remove(name)
    if name == 'nil' and self.optional == true then
        self.optional = nil
    end
    for index = #self, 1, -1 do
        local c = self[index]
        if
            (c.type == 'global' and c.cate == 'type' and c.name == name)
            or (c.type == name)
            or (c.type == 'doc.type.integer' and (name == 'number' or name == 'integer'))
            or (c.type == 'doc.type.boolean' and name == 'boolean')
            or (c.type == 'doc.type.boolean' and name == 'true' and c[1] == true)
            or (c.type == 'doc.type.boolean' and name == 'false' and c[1] == false)
            or (c.type == 'doc.type.table' and name == 'table')
            or (c.type == 'doc.type.array' and name == 'table')
            or (c.type == 'doc.type.sign' and name == c.node[1])
            or (c.type == 'doc.type.function' and name == 'function')
            or (c.type == 'doc.type.string' and name == 'string')
        then
            table.remove(self, index)
            self[c] = nil
        end
    end
    return self
end

--- @param uri string
--- @param name string
function Node:narrow(uri, name)
    if self.optional == true then
        self.optional = nil
    end
    for index = #self, 1, -1 do
        local c = self[index]
        if
            (c.type == name)
            or (c.type == 'doc.type.integer' and (name == 'number' or name == 'integer'))
            or (c.type == 'doc.type.boolean' and name == 'boolean')
            or (c.type == 'doc.type.table' and name == 'table')
            or (c.type == 'doc.type.array' and name == 'table')
            or (c.type == 'doc.type.sign' and name == c.node[1])
            or (c.type == 'doc.type.function' and name == 'function')
            or (c.type == 'doc.type.string' and name == 'string')
        then
        else
            if
                c.type == 'global'
                and c.cate == 'type'
                and ((c.name == name) or (vm.isSubType(uri, c.name, name)))
            then
            else
                table.remove(self, index)
                self[c] = nil
            end
        end
    end
    if #self == 0 then
        self[#self + 1] = vm.getGlobal('type', name)
    end
    return self
end

--- @param obj vm.object | vm.variable
function Node:removeObject(obj)
    for index, c in ipairs(self) do
        if c == obj then
            table.remove(self, index)
            self[c] = nil
            return
        end
    end
end

--- @param node vm.node
function Node:removeNode(node)
    for _, c in ipairs(node) do
        if c.type == 'global' and c.cate == 'type' then
            ---@cast c vm.global
            self:remove(c.name)
        elseif c.type == 'nil' then
            self:remove('nil')
        elseif c.type == 'boolean' or c.type == 'doc.type.boolean' then
            if c[1] == true then
                self:remove('true')
            else
                self:remove('false')
            end
        else
            ---@cast c -vm.global
            self:removeObject(c)
        end
    end
end

--- @param name string
--- @return boolean
function Node:hasType(name)
    for _, c in ipairs(self) do
        if c.type == 'global' and c.cate == 'type' and c.name == name then
            return true
        end
    end
    return false
end

--- @param name string
--- @return boolean
function Node:hasName(name)
    if name == 'nil' and self.optional == true then
        return true
    end
    for _, c in ipairs(self) do
        if c.type == 'global' and c.cate == 'type' and c.name == name then
            return true
        end
        if c.type == name then
            return true
        end
        -- TODO
    end
    return false
end

--- @return vm.node
function Node:asTable()
    self.optional = nil
    for index = #self, 1, -1 do
        local c = self[index]
        if c.type == 'table' or c.type == 'doc.type.table' or c.type == 'doc.type.array' then
        elseif
            c.type == 'doc.type.sign' and (c.node[1] == 'table' or not guide.isBasicType(c.node[1]))
        then
        elseif
            c.type == 'global'
            and c.cate == 'type'
            and (c.name == 'table' or not guide.isBasicType(c.name))
        then
        else
            table.remove(self, index)
            self[c] = nil
        end
    end
    return self
end

--- @return fun():vm.node.object
function Node:eachObject()
    local i = 0
    return function()
        i = i + 1
        return self[i]
    end
end

--- @return vm.node
function Node:copy()
    return vm.createNode(self)
end

--- @param source vm.node.object | vm.generic
--- @param node vm.node | vm.node.object
--- @param cover? boolean
--- @return vm.node
function vm.setNode(source, node, cover)
    if not node then
        if TEST then
            error('Can not set nil node')
        else
            log.error('Can not set nil node')
        end
    end
    if cover then
        assert(node.type == 'vm.node')
        ---@cast node vm.node
        nodeCache[source] = node
        return node
    end
    local me = nodeCache[source]
    if me then
        me:merge(node)
    else
        if node.type == 'vm.node' then
            me = node:copy()
        else
            me = vm.createNode(node)
        end
        nodeCache[source] = me
    end
    return me
end

--- @param source vm.node.object
--- @return vm.node?
function vm.getNode(source)
    return nodeCache[source]
end

--- @param source vm.object
function vm.removeNode(source)
    nodeCache[source] = nil
end

local lockCount = 0
local needClearCache = false
function vm.lockCache()
    lockCount = lockCount + 1
end

function vm.unlockCache()
    lockCount = lockCount - 1
    if needClearCache then
        needClearCache = false
        vm.clearNodeCache()
    end
end

function vm.clearNodeCache()
    if lockCount > 0 then
        needClearCache = true
        return
    end
    log.debug('clearNodeCache')
    nodeCache = {}
end

local ID = 0

--- @param a? vm.node | vm.node.object
--- @param b? vm.node | vm.node.object
--- @return vm.node
function vm.createNode(a, b)
    ID = ID + 1
    local node = setmetatable({ id = ID }, Node)
    if a then
        node:merge(a)
    end
    if b then
        node:merge(b)
    end
    return node
end

--- @type timer?
local delayTimer
files.watch(function(ev, uri)
    if ev == 'version' then
        if ws.isReady(uri) then
            if CACHEALIVE then
                if delayTimer then
                    delayTimer:restart()
                end
                delayTimer = timer.wait(1, function()
                    delayTimer = nil
                    vm.clearNodeCache()
                end)
            else
                vm.clearNodeCache()
            end
        end
    end
end)

ws.watch(function(ev, _uri)
    if ev == 'reload' then
        vm.clearNodeCache()
    end
end)
