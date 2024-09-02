local files = require('files')
local lang = require('language')
local guide = require('parser.guide')
local vm = require('vm')
local await = require('await')

local checkTypes = {
    'local',
    'setlocal',
    'setglobal',
    'setfield',
    'setindex',
    'setmethod',
    'tablefield',
    'tableindex',
    'tableexp',
}

--- @param source parser.object.base
--- @return boolean
local function hasMarkType(source)
    if not source.bindDocs then
        return false
    end
    for _, doc in ipairs(source.bindDocs) do
        if doc.type == 'doc.type' or doc.type == 'doc.class' then
            return true
        end
    end
    return false
end

--- @param source parser.object.base
--- @return boolean
local function hasMarkClass(source)
    if not source.bindDocs then
        return false
    end
    for _, doc in ipairs(source.bindDocs) do
        if doc.type == 'doc.class' then
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

    local delayer = await.newThrottledDelayer(15)
    ---@async
    --- @param source
    --- | parser.object.set
    --- | parser.object.local
    --- | parser.object.tablefield
    --- | parser.object.tableindex
    --- | parser.object.tableexp
    guide.eachSourceTypes(state.ast, checkTypes, function(source)
        local value = source.value
        if not value then
            return
        end
        delayer:delay()
        if source.type == 'setlocal' then
            --- @cast source parser.object.setlocal
            local locNode = vm.compileNode(source.node)
            if not locNode.hasDefined then
                return
            end
        end
        if value.type == 'nil' then
            --[[
            ---@class A
            local mt
            ---@type X
            mt._x = nil -- don't warn this
            ]]
            if hasMarkType(source) then
                return
            end
            if source.type == 'setfield' or source.type == 'setindex' then
                return
            end
        end

        local valueNode = vm.compileNode(value)
        if source.type == 'setindex' or source.type == 'tableexp' then
            -- boolean[1] = nil
            valueNode = valueNode:copy():removeOptional()
        end

        if value.type == 'getfield' or value.type == 'getindex' then
            -- Since the field cannot be type-narrowed,
            -- So remove the false value and check again
            valueNode = valueNode:copy():setTruthy()
        end

        local varNode = vm.compileNode(source)
        local errs = {}
        if vm.canCastType(uri, varNode, valueNode, errs) then
            return
        end

        -- local Cat = setmetatable({}, {__index = Animal}) allows inversion
        if hasMarkClass(source) then
            if vm.canCastType(uri, valueNode:copy():remove('table'), varNode) then
                return
            end
        end

        callback({
            start = source.start,
            finish = source.finish,
            message = lang.script('DIAG_ASSIGN_TYPE_MISMATCH', {
                def = vm.getInfer(varNode):view(uri),
                ref = vm.getInfer(valueNode):view(uri),
            }) .. '\n' .. vm.viewTypeErrorMessage(uri, errs),
        })
    end)
end
