local files = require('files')
local guide = require('parser.guide')
--- @class vm
local vm = require('vm.vm')
local config = require('config')

--- @class parser.object.base
--- @field package _castTargetHead? parser.object.base | vm.global | false
--- @field package _validVersions? table<string, boolean>
--- @field package _deprecated? parser.object.base | false
--- @field package _async? boolean
--- @field package _nodiscard? boolean

--- Get class and alias
--- @param suri string
--- @param name? string
--- @return parser.object.base[]
function vm.getDocSets(suri, name)
    if name then
        local global = vm.getGlobal('type', name)
        if not global then
            return {}
        end
        return global:getSets(suri)
    else
        return vm.getGlobalSets(suri, 'type')
    end
end

--- @param uri string
--- @return boolean
function vm.isMetaFile(uri)
    local status = files.getState(uri)
    if not status then
        return false
    end
    local cache = files.getCache(uri)
    if not cache then
        return false
    end
    if cache.isMeta ~= nil then
        return cache.isMeta
    end
    cache.isMeta = false
    if not status.ast.docs then
        return false
    end
    for _, doc in ipairs(status.ast.docs) do
        if doc.type == 'doc.meta' then
            cache.isMeta = true
            cache.metaName = doc.name
            return true
        end
    end
    return false
end

--- @param uri string
--- @return string?
function vm.getMetaName(uri)
    if not vm.isMetaFile(uri) then
        return nil
    end
    local cache = files.getCache(uri)
    if not cache then
        return nil
    end
    if not cache.metaName then
        return nil
    end
    return cache.metaName[1]
end

--- @param uri string
--- @return boolean
function vm.isMetaFileRequireable(uri)
    if not vm.isMetaFile(uri) then
        return false
    end
    return vm.getMetaName(uri) ~= '_'
end

--- @param doc parser.object.base
--- @return table<string, boolean>?
function vm.getValidVersions(doc)
    if doc.type ~= 'doc.version' then
        return
    end
    if doc._validVersions then
        return doc._validVersions
    end
    local valids = {
        ['Lua 5.1'] = false,
        ['Lua 5.2'] = false,
        ['Lua 5.3'] = false,
        ['Lua 5.4'] = false,
        ['LuaJIT'] = false,
    }
    for _, version in ipairs(doc.versions) do
        if version.ge and type(version.version) == 'number' then
            for ver in pairs(valids) do
                local verNumber = tonumber(ver:sub(-3))
                if verNumber and verNumber >= version.version then
                    valids[ver] = true
                end
            end
        elseif version.le and type(version.version) == 'number' then
            for ver in pairs(valids) do
                local verNumber = tonumber(ver:sub(-3))
                if verNumber and verNumber <= version.version then
                    valids[ver] = true
                end
            end
        elseif type(version.version) == 'number' then
            valids[('Lua %.1f'):format(version.version)] = true
        elseif 'JIT' == version.version then
            valids['LuaJIT'] = true
        end
    end
    if valids['Lua 5.1'] then
        valids['LuaJIT'] = true
    end
    doc._validVersions = valids
    return valids
end

--- @param value parser.object.base
--- @return parser.object.base?
local function getDeprecated(value)
    if not value.bindDocs then
        return nil
    end
    if value._deprecated ~= nil then
        return value._deprecated or nil
    end
    for _, doc in ipairs(value.bindDocs) do
        if doc.type == 'doc.deprecated' then
            value._deprecated = doc
            return doc
        elseif doc.type == 'doc.version' then
            local valids = vm.getValidVersions(doc)
            if valids and not valids[config.get(guide.getUri(value), 'Lua.runtime.version')] then
                value._deprecated = doc
                return doc
            end
        end
    end
    if value.type == 'function' then
        local doc = getDeprecated(value.parent)
        if doc then
            value._deprecated = doc
            return doc
        end
    end
    value._deprecated = false
    return nil
end

--- @param value parser.object.base
--- @param deep boolean?
--- @return parser.object.base?
function vm.getDeprecated(value, deep)
    if not deep then
        return getDeprecated(value)
    end

    local deprecated
    for _, def in ipairs(vm.getDefs(value) or {}) do
        if
            def.type == 'setglobal'
            or def.type == 'setfield'
            or def.type == 'setmethod'
            or def.type == 'setindex'
            or def.type == 'tablefield'
            or def.type == 'tableindex'
        then
            deprecated = getDeprecated(def)
            if not deprecated then
                return
            end
        end
    end
    return deprecated
end

--- @param  value parser.object.base
--- @return boolean
local function isAsync(value)
    if value.type == 'function' then
        if not value.bindDocs then
            return false
        end
        if value._async ~= nil then
            return value._async
        end
        for _, doc in ipairs(value.bindDocs) do
            if doc.type == 'doc.async' then
                value._async = true
                return true
            end
        end
        value._async = false
        return false
    end
    if value.type == 'main' then
        return true
    end
    return value.async == true
end

--- @param value parser.object.base
--- @param deep  boolean?
--- @return boolean
function vm.isAsync(value, deep)
    if isAsync(value) then
        return true
    end
    if deep then
        for _, def in ipairs(vm.getDefs(value) or {}) do
            if isAsync(def) then
                return true
            end
        end
    end
    return false
end

--- @param value parser.object.base
--- @return boolean
local function isNoDiscard(value)
    if value.type == 'function' then
        if not value.bindDocs then
            return false
        end
        if value._nodiscard ~= nil then
            return value._nodiscard
        end
        for _, doc in ipairs(value.bindDocs) do
            if doc.type == 'doc.nodiscard' then
                value._nodiscard = true
                return true
            end
        end
        value._nodiscard = false
        return false
    end
    return false
end

--- @param value parser.object.base
--- @param deep boolean?
--- @return boolean
function vm.isNoDiscard(value, deep)
    if isNoDiscard(value) then
        return true
    end
    if deep then
        for _, def in ipairs(vm.getDefs(value) or {}) do
            if isNoDiscard(def) then
                return true
            end
        end
    end
    return false
end

--- @param param parser.object.base
--- @return boolean
local function isCalledInFunction(param)
    if not param.ref then
        return false
    end
    local func = guide.getParentFunction(param)
    for _, ref in ipairs(param.ref) do
        if ref.type == 'getlocal' then
            if ref.parent.type == 'call' and guide.getParentFunction(ref) == func then
                return true
            elseif
                ref.parent.type == 'callargs'
                and ref.parent[1] == ref
                and guide.getParentFunction(ref) == func
            then
                if
                    ref.parent.parent.node.special == 'pcall'
                    or ref.parent.parent.node.special == 'xpcall'
                then
                    return true
                end
            end
        end
    end
    return false
end

--- @param node parser.object.base
--- @param index integer
--- @return boolean
local function isLinkedCall(node, index)
    for _, def in ipairs(vm.getDefs(node)) do
        if def.type == 'function' then
            local param = def.args and def.args[index]
            if param then
                if isCalledInFunction(param) then
                    return true
                end
            end
        end
    end
    return false
end

--- @param node parser.object.base
--- @param index integer
--- @return boolean
function vm.isLinkedCall(node, index)
    return isLinkedCall(node, index)
end

--- @param call parser.object.base
--- @return boolean
function vm.isAsyncCall(call)
    if vm.isAsync(call.node, true) then
        return true
    end
    if not call.args then
        return false
    end
    for i, arg in ipairs(call.args) do
        if vm.isAsync(arg, true) and isLinkedCall(call.node, i) then
            return true
        end
    end
    return false
end

--- @param doc parser.object.base
--- @param results table[]
local function makeDiagRange(doc, results)
    local names
    if doc.names then
        names = {}
        for _, nameUnit in ipairs(doc.names) do
            local name = nameUnit[1]
            names[name] = true
        end
    end
    local row = guide.rowColOf(doc.start)
    if doc.mode == 'disable-next-line' then
        results[#results + 1] = {
            mode = 'disable',
            names = names,
            row = row + 1,
            source = doc,
        }
        results[#results + 1] = {
            mode = 'enable',
            names = names,
            row = row + 2,
            source = doc,
        }
    elseif doc.mode == 'disable-line' then
        results[#results + 1] = {
            mode = 'disable',
            names = names,
            row = row,
            source = doc,
        }
        results[#results + 1] = {
            mode = 'enable',
            names = names,
            row = row + 1,
            source = doc,
        }
    elseif doc.mode == 'disable' then
        results[#results + 1] = {
            mode = 'disable',
            names = names,
            row = row + 1,
            source = doc,
        }
    elseif doc.mode == 'enable' then
        results[#results + 1] = {
            mode = 'enable',
            names = names,
            row = row + 1,
            source = doc,
        }
    end
end

--- @param uri string
--- @param position integer
--- @param name string
--- @param err? boolean
--- @return boolean
function vm.isDiagDisabledAt(uri, position, name, err)
    local status = files.getState(uri)
    if not status then
        return false
    end
    if not status.ast.docs then
        return false
    end
    local cache = files.getCache(uri)
    if not cache then
        return false
    end
    if not cache.diagnosticRanges then
        cache.diagnosticRanges = {}
        for _, doc in ipairs(status.ast.docs) do
            if doc.type == 'doc.diagnostic' then
                makeDiagRange(doc, cache.diagnosticRanges)
            end
        end
        table.sort(cache.diagnosticRanges, function(a, b)
            return a.row < b.row
        end)
    end
    if #cache.diagnosticRanges == 0 then
        return false
    end
    local myRow = guide.rowColOf(position)
    local count = 0
    for _, range in ipairs(cache.diagnosticRanges) do
        if range.row <= myRow then
            if (range.names and range.names[name]) or (not range.names and not err) then
                if range.mode == 'disable' then
                    count = count + 1
                elseif range.mode == 'enable' then
                    count = count - 1
                end
            end
        else
            break
        end
    end
    return count > 0
end

--- @param doc parser.object.base
--- @return (parser.object.base | vm.global)?
function vm.getCastTargetHead(doc)
    if doc._castTargetHead ~= nil then
        return doc._castTargetHead or nil
    end
    local name = doc.name[1]:match('^[^%.]+')
    if not name then
        doc._castTargetHead = false
        return nil
    end
    local loc = guide.getLocal(doc, name, doc.start)
    if loc then
        doc._castTargetHead = loc
        return loc
    end
    local global = vm.getGlobal('variable', name)
    if global then
        doc._castTargetHead = global
        return global
    end
    return nil
end

--- @param doc parser.object.base
--- @param key string
--- @return boolean
function vm.docHasAttr(doc, key)
    if not doc.docAttr then
        return false
    end
    for _, name in ipairs(doc.docAttr.names) do
        if name[1] == key then
            return true
        end
    end
    return false
end
