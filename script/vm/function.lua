--- @class vm
local vm = require('vm.vm')
local guide = require('parser.guide')
local util = require('utility')

--- @class parser.object.function
--- @field package _varargFunction? boolean

--- @param arg parser.object.base
--- @return parser.object.doc.param?
local function getDocParam(arg)
    for _, doc in ipairs(arg.bindDocs or {}) do
        if doc.type == 'doc.param' and doc.param[1] == arg[1] then
            --- @cast doc parser.object.doc.param
            return doc
        end
    end
end

--- @param func parser.object
--- @return integer min
--- @return number  max
--- @return integer def
function vm.countParamsOfFunction(func)
    local min = 0
    local max = 0
    local def = 0
    if func.type == 'function' then
        --- @cast func parser.object.function
        if func.args then
            max = #func.args
            def = max
            for i = #func.args, 1, -1 do
                local arg = func.args[i]
                if arg.type == '...' then
                    max = math.huge
                elseif arg.type == 'self' and i == 1 then
                    min = i
                    break
                elseif getDocParam(arg) and not vm.compileNode(arg):isNullable() then
                    min = i
                    break
                end
            end
        end
    elseif func.type == 'doc.type.function' then
        --- @cast func parser.object.doc.type.function
        if func.args then
            max = #func.args
            def = max
            for i = #func.args, 1, -1 do
                local arg = func.args[i]
                if arg.name and arg.name[1] == '...' then
                    max = math.huge
                elseif not vm.compileNode(arg):isNullable() then
                    min = i
                    break
                end
            end
        end
    end
    return min, max, def
end

--- @param source parser.object
--- @return integer min
--- @return number  max
--- @return integer def
function vm.countParamsOfSource(source)
    local min = 0
    local max = 0
    local def = 0
    local overloads = {}

    for _, doc in ipairs(source.bindDocs or {}) do
        if doc.type == 'doc.overload' then
            overloads[doc.overload] = true
        end
    end

    local hasDocFunction
    for nd in vm.compileNode(source):eachObject() do
        if nd.type == 'doc.type.function' and not overloads[nd] then
            hasDocFunction = true
            ---@cast nd parser.object.doc.type.function
            local dmin, dmax, ddef = vm.countParamsOfFunction(nd)
            min = math.max(min, dmin)
            max = math.max(max, dmax)
            def = math.max(def, ddef)
        end
    end

    if not hasDocFunction then
        local dmin, dmax, ddef = vm.countParamsOfFunction(source)
        min = math.max(min, dmin)
        max = math.max(max, dmax)
        def = math.max(def, ddef)
    end

    return min, max, def
end

--- @param node vm.node
--- @return integer min
--- @return number  max
--- @return integer def
function vm.countParamsOfNode(node)
    --- @type integer?, number?, integer?
    local min, max, def
    for n in node:eachObject() do
        if n.type == 'function' or n.type == 'doc.type.function' then
            --- @cast n parser.object.function|parser.object.doc.type.function
            local fmin, fmax, fdef = vm.countParamsOfFunction(n)
            min = math.min(min or 100000, fmin)
            max = math.max(max or 0, fmax)
            def = math.max(def or 0, fdef)
        end
    end
    return min or 0, max or math.huge, def or 0
end

--- @param func parser.object
--- @param onlyDoc? boolean
--- @param mark? table
--- @return integer min
--- @return number  max
--- @return integer def
function vm.countReturnsOfFunction(func, onlyDoc, mark)
    if func.type == 'function' then
        --- @cast func parser.object.function
        --- @type integer?, number?, integer?
        local min, max, def
        local hasDocReturn
        if func.bindDocs then
            local lastReturn
            local n = 0
            ---@type integer?, number?, integer?
            local dmin, dmax, ddef
            for _, doc in ipairs(func.bindDocs) do
                if doc.type == 'doc.return' then
                    --- @cast doc parser.object.doc.return
                    hasDocReturn = true
                    for _, ret in ipairs(doc.returns) do
                        n = n + 1
                        lastReturn = ret
                        dmax = n
                        ddef = n
                        if
                            (not ret.name or ret.name[1] ~= '...')
                            and not vm.compileNode(ret):isNullable()
                        then
                            dmin = n
                        end
                    end
                end
            end
            if lastReturn then
                if lastReturn.name and lastReturn.name[1] == '...' then
                    dmax = math.huge
                end
            end
            if dmin and (not min or (dmin < min)) then
                min = dmin
            end
            if dmax and (not max or (dmax > max)) then
                max = dmax
            end
            if ddef and (not def or (ddef > def)) then
                def = ddef
            end
        end
        if not onlyDoc and not hasDocReturn and func.returns then
            for _, ret in ipairs(func.returns) do
                local dmin, dmax, ddef = vm.countList(ret, mark)
                if not min or dmin < min then
                    min = dmin
                end
                if not max or dmax > max then
                    max = dmax
                end
                if not def or ddef > def then
                    def = ddef
                end
            end
        end
        return min or 0, max or math.huge, def or 0
    end

    if func.type == 'doc.type.function' then
        return vm.countList(func.returns)
    end

    error('not a function')
end

--- @param source parser.object
--- @return integer min
--- @return number  max
--- @return integer def
function vm.countReturnsOfSource(source)
    local overloads = {}
    local hasDocFunction
    local min, max, def
    for _, doc in ipairs(source.bindDocs or {}) do
        if doc.type == 'doc.overload' then
            overloads[doc.overload] = true
            local dmin, dmax, ddef = vm.countReturnsOfFunction(doc.overload)
            if not min or dmin < min then
                min = dmin
            end
            if not max or dmax > max then
                max = dmax
            end
            if not def or ddef > def then
                def = ddef
            end
        end
    end
    for nd in vm.compileNode(source):eachObject() do
        if nd.type == 'doc.type.function' and not overloads[nd] then
            --- @cast nd parser.object.doc.type.function
            hasDocFunction = true
            local dmin, dmax, ddef = vm.countReturnsOfFunction(nd)
            if not min or dmin < min then
                min = dmin
            end
            if not max or dmax > max then
                max = dmax
            end
            if not def or ddef > def then
                def = ddef
            end
        end
    end
    if not hasDocFunction then
        local dmin, dmax, ddef = vm.countReturnsOfFunction(source, true)
        if not min or dmin < min then
            min = dmin
        end
        if not max or dmax > max then
            max = dmax
        end
        if not def or ddef > def then
            def = ddef
        end
    end
    return min, max, def
end

--- @param func parser.object
--- @param mark? table
--- @return integer min
--- @return number  max
--- @return integer def
function vm.countReturnsOfCall(func, args, mark)
    local funcs = vm.getMatchedFunctions(func, args, mark)
    if not funcs then
        return 0, math.huge, 0
    end
    ---@type integer?, number?, integer?
    local min, max, def
    for _, f in ipairs(funcs) do
        local rmin, rmax, rdef = vm.countReturnsOfFunction(f, false, mark)
        if not min or rmin < min then
            min = rmin
        end
        if not max or rmax > max then
            max = rmax
        end
        if not def or rdef > def then
            def = rdef
        end
    end
    return min or 0, max or math.huge, def or 0
end

--- @param list parser.object[]?
--- @param mark? table
--- @return integer min
--- @return number  max
--- @return integer def
function vm.countList(list, mark)
    if not list then
        return 0, 0, 0
    end
    local lastArg = list[#list]
    if not lastArg then
        return 0, 0, 0
    end
    ---@type integer, number, integer
    local min, max, def = #list, #list, #list
    if
        lastArg.type == '...'
        or lastArg.type == 'varargs'
        or (lastArg.type == 'doc.type' and lastArg.name and lastArg.name[1] == '...')
    then
        max = math.huge
    elseif lastArg.type == 'call' then
        --- @cast lastArg parser.object.call
        mark = mark or {}
        if mark[lastArg] then
            min = min - 1
            max = math.huge
        else
            mark[lastArg] = true
            local rmin, rmax, rdef = vm.countReturnsOfCall(lastArg.node, lastArg.args, mark)
            return min - 1 + rmin, max - 1 + rmax, def - 1 + rdef
        end
    end
    for i = min, 1, -1 do
        local arg = list[i]
        if
            arg.type == 'doc.type'
            and ((arg.name and arg.name[1] == '...') or vm.compileNode(arg):isNullable())
        then
            min = i - 1
        else
            break
        end
    end
    return min, max, def
end

--- @param uri string
--- @param args parser.object[]
--- @return boolean
local function isAllParamMatched(uri, args, params)
    if not params then
        return false
    end
    for i = 1, #args do
        if not params[i] then
            break
        end
        local argNode = vm.compileNode(args[i])
        local defNode = vm.compileNode(params[i])
        if not vm.canCastType(uri, defNode, argNode) then
            return false
        end
    end
    return true
end

--- @param func parser.object
--- @param args? parser.object[]
--- @return parser.object[]?
function vm.getExactMatchedFunctions(func, args)
    local funcs = vm.getMatchedFunctions(func, args)
    if not args or not funcs then
        return funcs
    end
    if #funcs == 1 then
        return funcs
    end
    local uri = guide.getUri(func)
    local needRemove
    for i, n in ipairs(funcs) do
        if vm.isVarargFunctionWithOverloads(n) or not isAllParamMatched(uri, args, n.args) then
            needRemove = needRemove or {}
            needRemove[#needRemove + 1] = i
        end
    end
    if not needRemove then
        return funcs
    end
    if #needRemove == #funcs then
        return
    end
    util.tableMultiRemove(funcs, needRemove)
    return funcs
end

--- @param func parser.object
--- @param args? parser.object[]
--- @param mark? table
--- @return parser.object[]?
function vm.getMatchedFunctions(func, args, mark)
    local funcs = {}
    local node = vm.compileNode(func)
    for n in node:eachObject() do
        if n.type == 'function' or n.type == 'doc.type.function' then
            funcs[#funcs + 1] = n
        end
    end

    local amin, amax = vm.countList(args, mark)

    local matched = {}
    for _, n in ipairs(funcs) do
        local min, max = vm.countParamsOfFunction(n)
        if amin >= min and amax <= max then
            matched[#matched + 1] = n
        end
    end

    if #matched == 0 then
        return
    end
    return matched
end

--- @param func table
--- @return boolean
function vm.isVarargFunctionWithOverloads(func)
    if func.type ~= 'function' then
        return false
    end

    --- @cast func parser.object.function

    local args = func.args

    if not args then
        return false
    end

    if func._varargFunction ~= nil then
        return func._varargFunction
    end

    if args[1] and args[1].type == 'self' then
        if not args[2] or args[2].type ~= '...' then
            func._varargFunction = false
            return false
        end
    elseif not args[1] or args[1].type ~= '...' then
        func._varargFunction = false
        return false
    end

    for _, doc in ipairs(func.bindDocs or {}) do
        if doc.type == 'doc.overload' then
            func._varargFunction = true
            return true
        end
    end

    func._varargFunction = false
    return false
end

--- @param func parser.object.base
--- @return boolean
function vm.isEmptyFunction(func)
    if #func > 0 then
        return false
    end
    local startRow = guide.rowColOf(func.start)
    local finishRow = guide.rowColOf(func.finish)
    return finishRow - startRow <= 1
end
