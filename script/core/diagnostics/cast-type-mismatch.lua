local files = require('files')
local lang = require('language')
local vm = require('vm')
local await = require('await')

--- @param doc parser.object.doc.cast
local function checkCast(doc, uri, callback)
    local defs = vm.getDefs(doc.name)
    local loc = defs[1]
    if not loc then
        return
    end

    local defNode = vm.compileNode(loc)
    if not defNode.hasDefined then
        return
    end

    for _, cast in ipairs(doc.casts) do
        if not cast.mode and cast.extends then
            local refNode = vm.compileNode(cast.extends)
            local errs = {}
            if not vm.canCastType(uri, defNode, refNode, errs) then
                assert(errs)
                callback({
                    start = cast.extends.start,
                    finish = cast.extends.finish,
                    message = lang.script('DIAG_CAST_TYPE_MISMATCH', {
                        def = vm.getInfer(defNode):view(uri),
                        ref = vm.getInfer(refNode):view(uri),
                    })
                        .. '\n'
                        .. vm.viewTypeErrorMessage(uri, errs),
                })
            end
        end
    end
end

--- @async
return function(uri, callback)
    local state = files.getState(uri)
    if not state then
        return
    end

    if not state.ast.docs then
        return
    end

    for _, doc in ipairs(state.ast.docs) do
        if doc.type == 'doc.cast' and doc.name then
            --- @cast doc parser.object.doc.cast
            await.delay()
            checkCast(doc, uri, callback)
        end
    end
end
