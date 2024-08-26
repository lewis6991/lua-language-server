--- @class vm
local vm = require('vm.vm')
local guide = require('parser.guide')

--- @param source  parser.object.base
--- @param pushResult fun(src: parser.object.base)
local function searchBySimple(source, pushResult)
    if source.type == 'goto' then
        if source.node then
            pushResult(source.node)
        end
    elseif source.type == 'doc.cast.name' then
        local loc = guide.getLocal(source, source[1], source.start)
        if loc then
            pushResult(loc)
        end
    elseif source.type == 'doc.field' then
        pushResult(source)
    end
end

--- @param source  parser.object.base
--- @param pushResult fun(src: parser.object.base)
local function searchByLocalID(source, pushResult)
    local idSources = vm.getVariableSets(source)
    if not idSources then
        return
    end
    for _, src in ipairs(idSources) do
        pushResult(src)
    end
end

local function searchByNode(source, pushResult)
    local node = vm.compileNode(source)
    local suri = guide.getUri(source)
    for n in node:eachObject() do
        if n.type == 'global' then
            for _, set in ipairs(n:getSets(suri)) do
                pushResult(set)
            end
        else
            pushResult(n)
        end
    end
end

--- @param source parser.object.base
--- @return       parser.object.base[]
function vm.getDefs(source)
    local results = {}
    local mark = {}

    local hasLocal
    local function pushResult(src)
        if src.type == 'local' then
            if hasLocal then
                return
            end
            hasLocal = true
            if
                source.type ~= 'local'
                and source.type ~= 'getlocal'
                and source.type ~= 'setlocal'
                and source.type ~= 'doc.cast.name'
            then
                return
            end
        end
        if not mark[src] then
            mark[src] = true
            if guide.isAssign(src) or guide.isLiteral(src) then
                results[#results + 1] = src
            end
        end
    end

    searchBySimple(source, pushResult)
    searchByLocalID(source, pushResult)
    vm.compileByNodeChain(source, pushResult)
    searchByNode(source, pushResult)

    return results
end

local HAS_DEF_ERR = false -- the error object for comparing
local function checkHasDef(checkFunc, source, pushResult)
    local _, err = pcall(checkFunc, source, pushResult)
    return err == HAS_DEF_ERR
end

--- @param source parser.object.base
function vm.hasDef(source)
    local mark = {}
    local hasLocal
    local function pushResult(src)
        if src.type == 'local' then
            if hasLocal then
                return
            end
            hasLocal = true
            if
                source.type ~= 'local'
                and source.type ~= 'getlocal'
                and source.type ~= 'setlocal'
                and source.type ~= 'doc.cast.name'
            then
                return
            end
        end
        if not mark[src] then
            mark[src] = true
            if guide.isAssign(src) or guide.isLiteral(src) then
                -- break out on 1st result using error() with a unique error object
                error(HAS_DEF_ERR)
            end
        end
    end

    return checkHasDef(searchBySimple, source, pushResult)
        or checkHasDef(searchByLocalID, source, pushResult)
        or checkHasDef(vm.compileByNodeChain, source, pushResult)
        or checkHasDef(searchByNode, source, pushResult)
end
