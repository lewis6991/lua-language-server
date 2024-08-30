local util = require('utility')
local guide = require('parser.guide')
--- @class vm
local vm = require('vm.vm')

--- @class vm.variable
--- @field uri string
--- @field root parser.object
--- @field id string
--- @field base parser.object
--- @field sets parser.object[]
--- @field gets parser.object[]
local mt = {}
mt.__index = mt
mt.type = 'variable'

--- @param id string
--- @return vm.variable
local function createVariable(root, id)
    return setmetatable({
        root = root,
        uri = root.uri,
        id = id,
        sets = {},
        gets = {},
    }, mt)
end

--- @class parser.object.base
--- @field package _variableNode? vm.variable|false
--- @field package _variableNodes? table<string, vm.variable>

--- @param id string
--- @param source parser.object
--- @param base parser.object
--- @return vm.variable
local function insertVariableID(id, source, base)
    local root = guide.getRoot(source)
    if not root._variableNodes then
        root._variableNodes = util.multiTable(2, function(lid)
            local variable = createVariable(root, lid)
            return variable
        end)
    end
    local variable = root._variableNodes[id]
    variable.base = base
    local c = guide.isAssign(source) and variable.sets or variable.gets
    c[#c + 1] = source
    return variable
end

local compileVariables, getLocal

--- @type table<string|string[], fun(source: parser.object): parser.object?>
local leftswitch_table = {
    [{ 'field', 'method' }] = function(source)
        return getLocal(source.parent)
    end,

    [{ 'getfield', 'setfield', 'getmethod', 'setmethod', 'getindex', 'setindex' }] = function(
        source
    )
        return getLocal(source.node)
    end,

    ['getlocal'] = function(source)
        return source.node
    end,

    [{ 'self', 'local' }] = function(source)
        return source
    end,
}

local leftswitch = util.switch2(leftswitch_table)

--- @param source parser.object
--- @return parser.object?
function getLocal(source)
    return leftswitch(source.type)(source)
end

--- @return parser.object
function mt:getBase()
    return self.base
end

--- @return string
function mt:getCodeName()
    local name = self.id:gsub(vm.ID_SPLITE, '.'):gsub('^%d+', self.base[1])
    return name
end

--- @return vm.variable?
function mt:getParent()
    local parentID = self.id:match('^(.+)' .. vm.ID_SPLITE)
    if not parentID then
        return nil
    end
    return self.root._variableNodes[parentID]
end

--- @return string?
function mt:getFieldName()
    return self.id:match(vm.ID_SPLITE .. '(.-)$')
end

--- @param key?   string
function mt:getSets(key)
    if not key then
        return self.sets
    end
    local id = self.id .. vm.ID_SPLITE .. key
    local variable = self.root._variableNodes[id]
    return variable.sets
end

--- @param includeGets boolean?
function mt:getFields(includeGets)
    local id = self.id
    local root = self.root
    -- TODO：optimize
    local clock = os.clock()
    local fields = {}
    for lid, variable in pairs(root._variableNodes) do
        if
            lid ~= id
            and util.stringStartWith(lid, id)
            and lid:sub(#id + 1, #id + 1) == vm.ID_SPLITE
            -- only one field
            and not lid:find(vm.ID_SPLITE, #id + 2)
        then
            for _, src in ipairs(variable.sets) do
                fields[#fields + 1] = src
            end
            if includeGets then
                for _, src in ipairs(variable.gets) do
                    fields[#fields + 1] = src
                end
            end
        end
    end
    local cost = os.clock() - clock
    if cost > 1.0 then
        log.warn('variable-id getFields takes %.3f seconds', cost)
    end
    return fields
end

--- @type table<string|string[], fun(source: parser.object, base: parser.object)>
local variableCompilers_table = {
    [{ 'self', 'local' }] = function(source, base)
        local id = ('%d'):format(source.start)
        local variable = insertVariableID(id, source, base)
        source._variableNode = variable
        for _, ref in ipairs(source.ref or {}) do
            compileVariables(ref, base)
        end
    end,

    [{ 'getlocal', 'setlocal' }] = function(source, base)
        local id = ('%d'):format(source.node.start)
        local variable = insertVariableID(id, source, base)
        source._variableNode = variable
        compileVariables(source.next, base)
    end,

    [{ 'getfield', 'setfield', 'getmethod', 'setmethod', 'getindex', 'setindex' }] = function(source, base)
        local parentNode = source.node._variableNode
        if not parentNode then
            return
        end
        local key = guide.getKeyName(source)
        if type(key) ~= 'string' then
            return
        end
        local id = parentNode.id .. vm.ID_SPLITE .. key
        local variable = insertVariableID(id, source, base)
        source._variableNode = variable

        if source.type == 'getmethod' or source.type == 'setmethod' then
            source.method._variableNode = variable
        elseif source.type == 'getfield' or source.type == 'setfield' then
            source.field._variableNode = variable
        else
            source.index._variableNode = variable
        end

        if source.type == 'setindex' or source.type == 'getmethod' or source.type == 'getfield' then
            compileVariables(source.next, base)
        end
    end,
}

local variableCompilers = util.switch2(variableCompilers_table)

--- @param source parser.object
--- @param base parser.object
function compileVariables(source, base)
    if not source then
        return
    end
    source._variableNode = false

    variableCompilers(source.type)(source, base)
end

--- @param source parser.object
--- @return vm.variable?
local function getVariableNode(source)
    local variable = source._variableNode
    if variable ~= nil then
        return variable or nil
    end

    source._variableNode = false
    local loc = getLocal(source)
    if not loc then
        return
    end
    compileVariables(loc, loc)
    return source._variableNode or nil
end

--- @param source parser.object
--- @return string?
function vm.getVariableID(source)
    local variable = getVariableNode(source)
    if not variable then
        return nil
    end
    return variable.id
end

--- @param source parser.object
--- @param key?   string
--- @return vm.variable?
function vm.getVariable(source, key)
    local variable = getVariableNode(source)
    if not variable then
        return
    end
    if not key then
        return variable
    end
    local root = guide.getRoot(source)
    if not root._variableNodes then
        return
    end
    local id = variable.id .. vm.ID_SPLITE .. key
    return root._variableNodes[id]
end

--- @param source parser.object
--- @param key?   string
--- @return parser.object[]?
function vm.getVariableSets(source, key)
    local variable = vm.getVariable(source, key)
    if variable then
        return variable.sets
    end
end

--- @param source parser.object
--- @param key?   string
--- @return parser.object[]?
function vm.getVariableGets(source, key)
    local variable = vm.getVariable(source, key)
    if variable then
        return variable.gets
    end
end

--- @param source parser.object
--- @param includeGets boolean
--- @return parser.object[]?
function vm.getVariableFields(source, includeGets)
    local variable = vm.getVariable(source)
    if not variable then
        return nil
    end
    return variable:getFields(includeGets)
end

--- @param source parser.object
--- @return boolean
function vm.compileByVariable(source)
    local variable = getVariableNode(source)
    if not variable then
        return false
    end
    vm.setNode(source, variable)
    return true
end

--- @param source parser.object
local function compileSelf(source)
    if source.parent.type ~= 'funcargs' then
        return
    end
    ---@type parser.object
    local node = source.parent.parent
        and source.parent.parent.parent
        and source.parent.parent.parent.node
    if not node then
        return
    end
    local fields = vm.getVariableFields(source, false)
    if not fields then
        return
    end
    local variableNode = getVariableNode(node)
    local globalNode = vm.getGlobalNode(node)
    if not variableNode and not globalNode then
        return
    end
    for _, field in ipairs(fields) do
        if field.type == 'setfield' then
            local key = guide.getKeyName(field)
            if key then
                if variableNode then
                    local myID = variableNode.id .. vm.ID_SPLITE .. key
                    insertVariableID(myID, field, variableNode.base)
                end
                if globalNode then
                    local myID = globalNode:getName() .. vm.ID_SPLITE .. key
                    local myGlobal = vm.declareGlobal('variable', myID, guide.getUri(node))
                    myGlobal:addSet(guide.getUri(node), field)
                end
            end
        end
    end
end

--- @param source parser.object
local function compileAst(source)
    --[[
    local mt
    function mt:xxx()
        self.a = 1
    end

    mt.a --> find this definition
    ]]
    guide.eachSourceType(source, 'self', function(src)
        compileSelf(src)
    end)
end

return {
    compileAst = compileAst,
}
