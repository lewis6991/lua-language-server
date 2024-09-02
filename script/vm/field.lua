--- @class vm
local vm = require('vm.vm')
local guide = require('parser.guide')

local function searchByLocalID(source, pushResult)
    for _, field in ipairs(vm.getVariableFields(source, true) or {}) do
        pushResult(field)
    end
end

local function searchByNode(source, pushResult, mark)
    mark = mark or {}
    if mark[source] then
        return
    end
    mark[source] = true
    local uri = guide.getUri(source)
    vm.compileByParentNode(source, vm.ANY, function(field)
        if field.type == 'global' then
            --- @cast field vm.global
            for _, set in ipairs(field:getSets(uri)) do
                pushResult(set)
            end
        else
            pushResult(field)
        end
    end)
    vm.compileByNodeChain(source, function(src)
        searchByNode(src, pushResult, mark)
    end)
end

--- @param source parser.object.base
--- @return       parser.object.base[]
function vm.getFields(source)
    local results = {}
    local seen = {}

    local function pushResult(src)
        if not seen[src] then
            seen[src] = true
            results[#results + 1] = src
        end
    end

    searchByLocalID(source, pushResult)
    searchByNode(source, pushResult)

    return results
end
