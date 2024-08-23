local await = require('await')
local proto = require('proto.proto')
local define = require('proto.define')
local lang = require('language')
local files = require('files')
local config = require('config')
local core = require('core.diagnostics')
local util = require('utility')
local ws = require('workspace')
local progress = require('progress')
local client = require('client')
local converter = require('proto.converter')
local loading = require('workspace.loading')
local scope = require('workspace.scope')
local time = require('bee.time')
local ltable = require('linked-table')
local furi = require('file-uri')
local json = require('json')
local fw = require('filewatch')
local vm = require('vm.vm')

--- @class diagnosticProvider
local M = {}
M.cache = {}
M.sleepRest = 0.0
M.scopeDiagCount = 0
M.pauseCount = 0

local function concat(t, sep)
    if type(t) ~= 'table' then
        return t
    end
    return table.concat(t, sep)
end

---@param uri string
---@param err any
---@return table?
local function buildSyntaxError(uri, err)
    local state = files.getState(uri)
    local text = files.getText(uri)
    if not text or not state then
        return
    end
    local message = lang.script('PARSER_' .. err.type, err.info)

    if err.version then
        local version = err.info and err.info.version or config.get(uri, 'Lua.runtime.version')
        message = message
            .. ('(%s)'):format(lang.script('DIAG_NEED_VERSION', concat(err.version, '/'), version))
    end

    local related = err.info and err.info.related
    local relatedInformation
    if related then
        relatedInformation = {}
        for _, rel in ipairs(related) do
            local rmessage
            if rel.message then
                rmessage = lang.script('PARSER_' .. rel.message)
            else
                rmessage = text:sub(rel.start, rel.finish)
            end
            local relUri = rel.uri or uri
            local relState = files.getState(relUri)
            if relState then
                relatedInformation[#relatedInformation + 1] = {
                    message = rmessage,
                    location = converter.location(
                        relUri,
                        converter.packRange(relState, rel.start, rel.finish)
                    ),
                }
            end
        end
    end

    return {
        code = err.type:lower():gsub('_', '-'),
        range = converter.packRange(state, err.start, err.finish),
        severity = define.DiagnosticSeverity[err.level],
        source = lang.script.DIAG_SYNTAX_CHECK,
        message = message,
        data = 'syntax',

        relatedInformation = relatedInformation,
    }
end

local function buildDiagnostic(uri, diag)
    local state = files.getState(uri)
    if not state then
        return
    end

    local relatedInformation
    if diag.related then
        relatedInformation = {}
        for _, rel in ipairs(diag.related) do
            local rtext = files.getText(rel.uri)
            if rtext then
                local relState = files.getState(rel.uri)
                if relState then
                    relatedInformation[#relatedInformation + 1] = {
                        message = rel.message or rtext:sub(rel.start, rel.finish),
                        location = converter.location(
                            rel.uri,
                            converter.packRange(relState, rel.start, rel.finish)
                        ),
                    }
                end
            end
        end
    end

    return {
        range = converter.packRange(state, diag.start, diag.finish),
        source = lang.script.DIAG_DIAGNOSTICS,
        severity = diag.level,
        message = diag.message,
        code = diag.code,
        tags = diag.tags,
        data = diag.data,

        relatedInformation = relatedInformation,
    }
end

local function mergeDiags(a, b, c)
    if not a and not b and not c then
        return nil
    end
    local t = {}

    local function merge(diags)
        if not diags then
            return
        end
        for i = 1, #diags do
            local diag = diags[i]
            local severity = diag.severity
            if
                severity ~= define.DiagnosticSeverity.Hint
                    and severity ~= define.DiagnosticSeverity.Information
                or #t <= 10000
            then
                t[#t + 1] = diag
            end
        end
    end

    merge(a)
    merge(b)
    merge(c)

    if #t > 0 then
        return t
    end
end

-- enable `push`, disable `clear`
function M.clear(uri, force)
    await.close('diag:' .. uri)
    if M.cache[uri] == nil and not force then
        return
    end
    M.cache[uri] = nil
    proto.notify('textDocument/publishDiagnostics', {
        uri = uri,
        diagnostics = {},
    })
    log.info('clearDiagnostics', uri)
end

function M.clearCacheExcept(uris)
    local excepts = {}
    for _, uri in ipairs(uris) do
        excepts[uri] = true
    end
    for uri in pairs(M.cache) do
        if not excepts[uri] then
            M.cache[uri] = false
        end
    end
end

--- @param uri? string
--- @param force? boolean
function M.clearAll(uri, force)
    local scp
    if uri then
        scp = scope.getScope(uri)
    end
    if force then
        for luri in files.eachFile() do
            if not scp or scope.getScope(luri) == scp then
                M.clear(luri, force)
            end
        end
    else
        for luri in pairs(M.cache) do
            if not scp or scope.getScope(luri) == scp then
                M.clear(luri)
            end
        end
    end
end

function M.syntaxErrors(uri, ast)
    if #ast.errs == 0 then
        return nil
    end

    local results = {}

    pcall(function()
        local disables = util.arrayToHash(config.get(uri, 'Lua.diagnostics.disable'))
        for _, err in ipairs(ast.errs) do
            local id = err.type:lower():gsub('_', '-')
            if not disables[id] and not vm.isDiagDisabledAt(uri, err.start, id, true) then
                results[#results + 1] = buildSyntaxError(uri, err)
            end
        end
    end)

    return results
end

local function copyDiagsWithoutSyntax(diags)
    if not diags then
        return nil
    end
    local copyed = {}
    for _, diag in ipairs(diags) do
        if diag.data ~= 'syntax' then
            copyed[#copyed + 1] = diag
        end
    end
    return copyed
end

--- @async
--- @param uri string
--- @return boolean
local function isValid(uri)
    if not config.get(uri, 'Lua.diagnostics.enable') then
        return false
    end
    if not ws.isReady(uri) then
        return false
    end
    if files.isLibrary(uri, true) then
        local status = config.get(uri, 'Lua.diagnostics.libraryFiles')
        if status == 'Disable' then
            return false
        elseif status == 'Opened' then
            if not files.isOpen(uri) then
                return false
            end
        end
    end
    if ws.isIgnored(uri) then
        local status = config.get(uri, 'Lua.diagnostics.ignoredFiles')
        if status == 'Disable' then
            return false
        elseif status == 'Opened' then
            if not files.isOpen(uri) then
                return false
            end
        end
    end
    local scheme = furi.split(uri)
    local disableScheme = config.get(uri, 'Lua.diagnostics.disableScheme')
    if util.arrayHas(disableScheme, scheme) then
        return false
    end
    return true
end

--- @async
function M.doDiagnostic(uri, isScopeDiag, ignoreFileState)
    if not isValid(uri) then
        return
    end

    await.delay()

    local state = files.getState(uri)
    if not state then
        M.clear(uri)
        return
    end

    local version = files.getVersion(uri)

    local prog <close> = progress.create(uri, lang.script.WINDOW_DIAGNOSING, 0.5)
    prog:setMessage(ws.getRelativePath(uri))

    --log.debug('Diagnostic file:', uri)

    local syntax = M.syntaxErrors(uri, state)

    local diags = {}
    local lastDiag = copyDiagsWithoutSyntax(M.cache[uri])
    local function pushResult()
        tracy.ZoneBeginN('mergeSyntaxAndDiags')
        local _ <close> = tracy.ZoneEnd
        local full = mergeDiags(syntax, lastDiag, diags)
        --log.debug(('Pushed [%d] results'):format(full and #full or 0))
        if not full then
            M.clear(uri)
            return
        end

        if util.equal(M.cache[uri], full) then
            return
        end
        M.cache[uri] = full

        if not files.exists(uri) then
            M.clear(uri)
            return
        end

        proto.notify('textDocument/publishDiagnostics', {
            uri = uri,
            version = version,
            diagnostics = full,
        })
        log.debug('publishDiagnostics', uri, #full)
    end

    pushResult()

    local lastPushClock = time.time()
    ---@async
    xpcall(core, log.error, uri, isScopeDiag, function(result)
        diags[#diags + 1] = buildDiagnostic(uri, result)

        if not isScopeDiag and time.time() - lastPushClock >= 500 then
            lastPushClock = time.time()
            pushResult()
        end
    end, function(checkedName)
        if not lastDiag then
            return
        end
        for i, diag in ipairs(lastDiag) do
            if diag.code == checkedName then
                lastDiag[i] = lastDiag[#lastDiag]
                lastDiag[#lastDiag] = nil
            end
        end
    end, ignoreFileState)

    lastDiag = nil
    pushResult()
end

--- @param uri string
function M.resendDiagnostic(uri)
    local full = M.cache[uri]
    if not full then
        return
    end

    if not files.exists(uri) then
        M.clear(uri)
        return
    end

    local version = files.getVersion(uri)

    proto.notify('textDocument/publishDiagnostics', {
        uri = uri,
        version = version,
        diagnostics = full,
    })
    log.debug('publishDiagnostics', uri, #full)
end

--- @async
--- @return table|nil result
--- @return boolean? unchanged
function M.pullDiagnostic(uri, isScopeDiag)
    if not isValid(uri) then
        return nil, util.equal(M.cache[uri], nil)
    end

    await.delay()

    local state = files.getState(uri)
    if not state then
        return nil, util.equal(M.cache[uri], nil)
    end

    local prog <close> = progress.create(uri, lang.script.WINDOW_DIAGNOSING, 0.5)
    prog:setMessage(ws.getRelativePath(uri))

    local syntax = M.syntaxErrors(uri, state)
    local diags = {}

    xpcall(core, log.error, uri, isScopeDiag, function(result)
        diags[#diags + 1] = buildDiagnostic(uri, result)
    end)

    local full = mergeDiags(syntax, diags)

    if util.equal(M.cache[uri], full) then
        return full, true
    end

    M.cache[uri] = full

    return full
end

--- @param uri string
function M.stopScopeDiag(uri)
    local scp = scope.getScope(uri)
    local scopeID = 'diagnosticsScope:' .. scp:getName()
    await.close(scopeID)
end

--- @param event string
--- @param uri string
function M.refreshScopeDiag(event, uri)
    if not ws.isReady(uri) then
        return
    end

    local eventConfig = config.get(uri, 'Lua.diagnostics.workspaceEvent')

    if eventConfig ~= event then
        return
    end

    ---@async
    await.call(function()
        local delay = config.get(uri, 'Lua.diagnostics.workspaceDelay') / 1000
        if delay < 0 then
            return
        end
        await.sleep(math.max(delay, 0.2))
        M.diagnosticsScope(uri)
    end)
end

--- @param uri string
function M.refresh(uri)
    if not ws.isReady(uri) then
        return
    end

    await.close('diag:' .. uri)
    ---@async
    await.call(function()
        await.setID('diag:' .. uri)
        repeat
            await.sleep(0.1)
        until not M.isPaused()
        xpcall(M.doDiagnostic, log.error, uri)
    end)
end

--- @async
local function askForDisable(uri)
    if M.dontAskedForDisable then
        return
    end
    local delay = 30
    local delayTitle = lang.script('WINDOW_DELAY_WS_DIAGNOSTIC', delay)
    local item = proto.awaitRequest('window/showMessageRequest', {
        type = define.MessageType.Info,
        message = lang.script.WINDOW_SETTING_WS_DIAGNOSTIC,
        actions = {
            {
                title = lang.script.WINDOW_DONT_SHOW_AGAIN,
            },
            {
                title = delayTitle,
            },
            {
                title = lang.script.WINDOW_DISABLE_DIAGNOSTIC,
            },
        },
    })
    if not item then
        return
    end
    if item.title == lang.script.WINDOW_DONT_SHOW_AGAIN then
        M.dontAskedForDisable = true
    elseif item.title == delayTitle then
        client.setConfig({
            {
                key = 'Lua.diagnostics.workspaceDelay',
                action = 'set',
                value = delay * 1000,
                uri = uri,
            },
        })
    elseif item.title == lang.script.WINDOW_DISABLE_DIAGNOSTIC then
        client.setConfig({
            {
                key = 'Lua.diagnostics.workspaceDelay',
                action = 'set',
                value = -1,
                uri = uri,
            },
        })
    end
end

local function clearMemory(finished)
    if M.scopeDiagCount > 0 then
        return
    end
    vm.clearNodeCache()
    if finished then
        collectgarbage()
        collectgarbage()
    end
end

--- @async
function M.awaitDiagnosticsScope(suri, callback)
    local scp = scope.getScope(suri)
    if scp.type == 'fallback' then
        return
    end
    while loading.count() > 0 do
        await.sleep(1.0)
    end
    local finished
    M.scopeDiagCount = M.scopeDiagCount + 1
    local scopeDiag <close> = util.defer(function()
        M.scopeDiagCount = M.scopeDiagCount - 1
        clearMemory(finished)
    end)
    local clock = os.clock()
    local bar <close> = progress.create(suri, lang.script.WORKSPACE_DIAGNOSTIC, 1)
    local cancelled
    bar:onCancel(function()
        log.info('Cancel workspace diagnostics')
        cancelled = true
        ---@async
        await.call(function()
            askForDisable(suri)
        end)
    end)
    local uris = files.getAllUris(suri)
    local sortedUris = ltable()
    for _, uri in ipairs(uris) do
        if files.isOpen(uri) then
            sortedUris:pushHead(uri)
        else
            sortedUris:pushTail(uri)
        end
    end
    log.info(('Diagnostics scope [%s], files count:[%d]'):format(scp:getName(), #uris))
    local i = 0
    for uri in sortedUris:pairs() do
        while loading.count() > 0 do
            await.sleep(1.0)
        end
        i = i + 1
        bar:setMessage(('%d/%d'):format(i, #uris))
        bar:setPercentage(i / #uris * 100)
        callback(uri)
        await.delay()
        if cancelled then
            log.info('Break workspace diagnostics')
            break
        end
    end
    bar:remove()
    log.info(
        ('Diagnostics scope [%s] finished, takes [%.3f] sec.'):format(
            scp:getName(),
            os.clock() - clock
        )
    )
    finished = true
end

function M.diagnosticsScope(uri, force, ignoreFileOpenState)
    if not ws.isReady(uri) then
        return
    end
    if not force and not config.get(uri, 'Lua.diagnostics.enable') then
        M.clearAll(uri)
        return
    end
    if not force and config.get(uri, 'Lua.diagnostics.workspaceDelay') < 0 then
        return
    end
    local scp = scope.getScope(uri)
    local id = 'diagnosticsScope:' .. scp:getName()
    await.close(id)
    await.call(function() ---@async
        await.sleep(0.0)
        M.awaitDiagnosticsScope(uri, function(fileUri)
            xpcall(M.doDiagnostic, log.error, fileUri, true, ignoreFileOpenState)
        end)
    end, id)
end

--- @async
function M.pullDiagnosticScope(callback)
    local processing = 0

    for _, scp in ipairs(scope.folders) do
        if ws.isReady(scp.uri) and config.get(scp.uri, 'Lua.diagnostics.enable') then
            local id = 'diagnosticsScope:' .. scp:getName()
            await.close(id)
            await.call(function() ---@async
                processing = processing + 1
                local _ <close> = util.defer(function()
                    processing = processing - 1
                end)

                local delay = config.get(scp.uri, 'Lua.diagnostics.workspaceDelay') / 1000
                if delay < 0 then
                    return
                end
                print(delay)
                await.sleep(math.max(delay, 0.2))
                print('start')

                M.awaitDiagnosticsScope(scp.uri, function(fileUri)
                    local suc, result, unchanged =
                        xpcall(M.pullDiagnostic, log.error, fileUri, true)
                    if suc then
                        callback({
                            uri = fileUri,
                            result = result,
                            unchanged = unchanged,
                            version = files.getVersion(fileUri),
                        })
                    end
                end)
            end, id)
        end
    end

    -- sleep for ever
    while true do
        await.sleep(1.0)
    end
end

function M.refreshClient()
    if not client.isReady() then
        return
    end
    if not client.getAbility('workspace.diagnostics.refreshSupport') then
        return
    end
    log.debug('Refresh client diagnostics')
    proto.request('workspace/diagnostic/refresh', json.null)
end

--- @return boolean
function M.isPaused()
    return M.pauseCount > 0
end

function M.pause()
    M.pauseCount = M.pauseCount + 1
end

function M.resume()
    M.pauseCount = M.pauseCount - 1
end

ws.watch(function(ev, uri)
    if ev == 'reload' then
        M.diagnosticsScope(uri)
        M.refreshClient()
    end
end)

files.watch(function(ev, uri) ---@async
    if ev == 'remove' then
        M.clear(uri)
        M.stopScopeDiag(uri)
        M.refresh(uri)
        M.refreshScopeDiag('OnSave', uri)
    elseif ev == 'create' then
        M.stopScopeDiag(uri)
        M.refresh(uri)
        M.refreshScopeDiag('OnSave', uri)
    elseif ev == 'update' then
        M.stopScopeDiag(uri)
        M.refresh(uri)
        M.refreshScopeDiag('OnChange', uri)
    elseif ev == 'open' then
        if ws.isReady(uri) then
            M.resendDiagnostic(uri)
            xpcall(M.doDiagnostic, log.error, uri)
        end
    elseif ev == 'close' then
        if files.isLibrary(uri, true) or ws.isIgnored(uri) then
            M.clear(uri)
        end
    elseif ev == 'save' then
        M.refreshScopeDiag('OnSave', uri)
    end
end)

config.watch(function(uri, key, value, oldValue)
    if
        util.stringStartWith(key, 'Lua.diagnostics')
        or util.stringStartWith(key, 'Lua.spell')
        or util.stringStartWith(key, 'Lua.doc')
    then
        if value ~= oldValue then
            M.diagnosticsScope(uri)
            M.refreshClient()
        end
    end
end)

fw.event(function(_ev, path)
    if util.stringEndWith(path, '.editorconfig') then
        for _, scp in ipairs(ws.folders) do
            M.diagnosticsScope(scp.uri)
            M.refreshClient()
        end
    end
end)

return M
