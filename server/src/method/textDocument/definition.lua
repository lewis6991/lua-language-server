local core = require 'core'

local function checkWorkSpaceComplete(lsp, source)
    if not source:bindValue() then
        return
    end
    if not source:bindValue():get 'cross file' then
        return
    end
    lsp:checkWorkSpaceComplete()
end

local function findResult(lsp, params)
    local uri = params.textDocument.uri
    local vm, lines = lsp:loadVM(uri)
    if not vm then
        return nil
    end

    -- lua是从1开始的，因此都要+1
    local position = lines:positionAsChar(params.position.line + 1, params.position.character)
    local source = core.findSource(vm, position)
    if not source then
        return nil
    end

    checkWorkSpaceComplete(lsp, source)

    local positions = core.definition(vm, source, lsp)
    if not positions then
        return nil
    end

    local locations = {}
    for i, position in ipairs(positions) do
        local start, finish, valueUri = position[1], position[2], (position[3] or uri)
        local _, valueLines = lsp:loadVM(valueUri)
        if valueLines then
            local start_row,  start_col  = valueLines:rowcol(start)
            local finish_row, finish_col = valueLines:rowcol(finish)
            locations[i] = {
                uri =  valueUri,
                range = {
                    start = {
                        line = start_row - 1,
                        character = start_col - 1,
                    },
                    ['end'] = {
                        line = finish_row - 1,
                        -- 这里不用-1，因为前端期待的是匹配完成后的位置
                        character = finish_col,
                    },
                }
            }
        end
    end

    if #locations == 0 then
        return nil
    end

    return locations
end

local LastTask

return function (lsp, params)
    if LastTask then
        LastTask:remove()
        LastTask = nil
    end
    local result = findResult(lsp, params)
    if result then
        return result
    end
    return function (response)
        LastTask = ac.loop(0.1, function ()
            local result = findResult(lsp, params)
            if result then
                response(result)
            end
            if lsp:isWaitingCompile() then
                return
            end
            LastTask:remove()
            LastTask = nil
            if not result then
                response(nil)
            end
        end)
    end
end
