local platform = require('bee.platform')
local fs = require('bee.filesystem')
local config = require('config')
local glob = require('glob')
local furi = require('file-uri')
local parser = require('parser')
local lang = require('language')
local await = require('await')
local util = require('utility')
local smerger = require('string-merger')
local progress = require('progress')
local encoder = require('encoder')
local scope = require('workspace.scope')
local lazy = require('lazytable')
local cacher = require('lazy-cacher')
local sp = require('bee.subprocess')
local pub = require('pub')

--- @class file
--- @field uri           string
--- @field ref?          integer
--- @field trusted?      boolean
--- @field rows?         integer[]
--- @field originText?   string
--- @field text?         string
--- @field version?      integer
--- @field originLines?  integer[]
--- @field diffInfo?     table[]
--- @field cache?        table
--- @field id            integer
--- @field state?        parser.state
--- @field compileCount? integer
--- @field words?        table

--- @class files
--- @field lazyCache?   lazy-cacher
local M = {}

M.watchList = {}
M.notifyCache = {}
M.assocVersion = -1

function M.reset()
  M.openMap = {}
  ---@type table<string, file>
  M.fileMap = {}
  M.dllMap = {}
  M.visible = {}
  M.globalVersion = 0
  M.fileCount = 0
  ---@type table<string, parser.state>
  M.stateMap = setmetatable({}, util.MODE_V)
  ---@type table<parser.state, true>
  M.stateTrace = setmetatable({}, util.MODE_K)
end

M.reset()

local fileID = util.counter()

local uriMap = {}

--- @param path fs.path
--- @return fs.path
local function getRealParent(path)
  local parent = path:parent_path()
  if parent:string():gsub('^%w+:', string.lower) == path:string():gsub('^%w+:', string.lower) then
    return path
  end
  local res = fs.fullpath(path)
  return getRealParent(parent) / res:filename()
end

--- Get the real uri of the file, but do not penetrate the soft link
--- @param uri string
--- @return string
function M.getRealUri(uri)
  if platform.os ~= 'windows' then
    return furi.normalize(uri)
  end
  if not furi.isValid(uri) then
    return uri
  end
  local filename = furi.decode(uri)
  -- normalize uri
  uri = furi.encode(filename)
  local path = fs.path(filename)
  local suc, exists = pcall(fs.exists, path)
  if not suc or not exists then
    return uri
  end
  local suc, res = pcall(fs.canonical, path)
  if not suc then
    return uri
  end
  filename = res:string()
  local ruri = furi.encode(filename)
  if uri == ruri then
    return ruri
  end
  local real = getRealParent(path:parent_path()) / res:filename()
  ruri = furi.encode(real:string())
  if uri == ruri then
    return ruri
  end
  if not uriMap[uri] then
    uriMap[uri] = true
    log.warn(('Fix real file uri: %s -> %s'):format(uri, ruri))
  end
  return ruri
end

--- Open file
--- @param uri string
function M.open(uri)
  M.openMap[uri] = {
    cache = {},
  }
  M.onWatch('open', uri)
end

--- Close file
--- @param uri string
function M.close(uri)
  M.openMap[uri] = nil
  local file = M.fileMap[uri]
  if file then
    file.trusted = false
  end
  M.onWatch('close', uri)
  if file then
    if (file.ref or 0) <= 0 and not M.isOpen(uri) then
      M.remove(uri)
    end
  end
end

--- Whether to open
--- @param uri string
--- @return boolean
function M.isOpen(uri)
  return M.openMap[uri] ~= nil
end

function M.getOpenedCache(uri)
  local data = M.openMap[uri]
  if not data then
    return nil
  end
  return data.cache
end

--- Whether it is a library file
function M.isLibrary(uri, excludeFolder)
  if excludeFolder then
    for _, scp in ipairs(scope.folders) do
      if scp:isChildUri(uri) then
        return false
      end
    end
  end
  for _, scp in ipairs(scope.folders) do
    if scp:isLinkedUri(uri) then
      return true
    end
  end
  if scope.fallback:isLinkedUri(uri) then
    return true
  end
  return false
end

--- Get the root directory of the library file
--- @return string?
function M.getLibraryUri(suri, uri)
  local scp = scope.getScope(suri)
  return scp:getLinkedUri(uri)
end

--- Does it exist
--- @return boolean
function M.exists(uri)
  return M.fileMap[uri] ~= nil
end

--- @param file file
--- @param text string
--- @return string
local function pluginOnSetText(file, text)
  local plugin = require('plugin')
  file.diffInfo = nil
  local suc, result = plugin.dispatch('OnSetText', file.uri, text)
  if not suc then
    if DEVELOP and result then
      util.saveFile(LOGPATH .. '/diffed.lua', tostring(result))
    end
    return text
  end
  if type(result) == 'string' then
    return result
  elseif type(result) == 'table' then
    local diffs
    suc, result, diffs = xpcall(smerger.mergeDiff, log.error, text, result)
    if suc then
      file.diffInfo = diffs
      file.originLines = parser.lines(text)
      return result
    else
      if DEVELOP and result then
        util.saveFile(LOGPATH .. '/diffed.lua', tostring(result))
      end
    end
  end
  return text
end

--- @param file file
function M.removeState(file)
  file.state = nil
  M.stateMap[file.uri] = nil
end

--- Set file text
--- @param uri string
--- @param text? string
--- @param isTrust? boolean
--- @param callback? function
function M.setText(uri, text, isTrust, callback)
  if not text then
    return
  end
  if #text > 1024 * 1024 * 10 then
    local client = require('client')
    client.showMessage('Warning', lang.script('WORKSPACE_SKIP_HUGE_FILE', uri))
    return
  end
  --log.debug('setText', uri)
  local create
  if not M.fileMap[uri] then
    M.fileMap[uri] = {
      uri = uri,
      id = fileID(),
    }
    M.fileCount = M.fileCount + 1
    create = true
    M._pairsCache = nil
  end
  local file = M.fileMap[uri]
  if file.trusted and not isTrust then
    return
  end
  if not isTrust then
    local encoding = config.get(uri, 'Lua.runtime.fileEncoding')
    text = encoder.decode(encoding, text)
  end
  if callback then
    callback(file)
  end
  if file.originText == text then
    return
  end
  local clock = os.clock()
  local newText = pluginOnSetText(file, text)
  M.removeState(file)
  file.text = newText
  file.trusted = isTrust
  file.originText = text
  file.rows = nil
  file.words = nil
  file.compileCount = 0
  file.cache = {}
  M.globalVersion = M.globalVersion + 1
  M.onWatch('version', uri)
  if create then
    M.onWatch('create', uri)
    M.onWatch('update', uri)
  else
    M.onWatch('update', uri)
  end
  if DEVELOP then
    if text ~= newText then
      util.saveFile(LOGPATH .. '/diffed.lua', newText)
    end
  end
  log.trace('Set text:', uri, 'takes', os.clock() - clock, 'sec.')

  --if instance or TEST then
  --else
  --    await.call(function ()
  --        await.close('update:' .. uri)
  --        await.setID('update:' .. uri)
  --        await.sleep(0.1)
  --        if m.exists(uri) then
  --            m.onWatch('update', uri)
  --        end
  --    end)
  --end
end

function M.resetText(uri)
  local file = M.fileMap[uri]
  if not file then
    return
  end
  local originText = file.originText
  file.originText = nil
  M.setText(uri, originText, file.trusted)
end

function M.setRawText(uri, text)
  if not text then
    return
  end
  local file = M.fileMap[uri]
  file.text = text
  file.originText = text
  M.removeState(file)
end

function M.getCachedRows(uri)
  local file = M.fileMap[uri]
  if not file then
    return nil
  end
  return file.rows
end

function M.setCachedRows(uri, rows)
  local file = M.fileMap[uri]
  if not file then
    return
  end
  file.rows = rows
end

function M.getWords(uri)
  local file = M.fileMap[uri]
  if not file then
    return
  end
  if file.words then
    return file.words
  end
  local words = {}
  file.words = words
  local text = file.text
  if not text then
    return
  end
  local mark = {}
  for word in text:gmatch('([%a_][%w_]+)') do
    if #word >= 3 and not mark[word] then
      mark[word] = true
      local head = word:sub(1, 2)
      if not words[head] then
        words[head] = {}
      end
      words[head][#words[head] + 1] = word
    end
  end
  return words
end

function M.getWordsOfHead(uri, head)
  local file = M.fileMap[uri]
  if not file then
    return nil
  end
  local words = M.getWords(uri)
  if not words then
    return nil
  end
  return words[head]
end

--- Get file version
function M.getVersion(uri)
  local file = M.fileMap[uri]
  if not file then
    return nil
  end
  return file.version
end

--- Get file text
--- @param uri string
--- @return string? text
function M.getText(uri)
  local file = M.fileMap[uri]
  if not file then
    return nil
  end
  return file.text
end

--- Get the original text of the file
--- @param uri string
--- @return string? text
function M.getOriginText(uri)
  local file = M.fileMap[uri]
  if not file then
    return nil
  end
  return file.originText
end

--- @param uri string
--- @param text string
function M.setOriginText(uri, text)
  local file = M.fileMap[uri]
  if not file then
    return
  end
  file.originText = text
end

--- Get the original line table of the file
--- @param uri string
--- @return integer[]
function M.getOriginLines(uri)
  local file = M.fileMap[uri]
  assert(file, 'file not exists:' .. uri)
  return file.originLines
end

function M.getChildFiles(uri)
  local results = {}
  local uris = M.getAllUris(uri)
  for _, curi in ipairs(uris) do
    if
      #curi > #uri
      and curi:sub(1, #uri) == uri
      and curi:sub(#uri + 1, #uri + 1):match('[/\\]')
    then
      results[#results + 1] = curi
    end
  end
  return results
end

function M.addRef(uri)
  local file = M.fileMap[uri]
  if not file then
    return nil
  end
  file.ref = (file.ref or 0) + 1
  log.debug('add ref', uri, file.ref)
  return function()
    M.delRef(uri)
  end
end

function M.delRef(uri)
  local file = M.fileMap[uri]
  if not file then
    return
  end
  file.ref = (file.ref or 0) - 1
  log.debug('del ref', uri, file.ref)
  if file.ref <= 0 and not M.isOpen(uri) then
    M.remove(uri)
  end
end

--- Remove files
--- @param uri string
function M.remove(uri)
  local file = M.fileMap[uri]
  if not file then
    return
  end
  M.removeState(file)
  M.fileMap[uri] = nil
  M._pairsCache = nil

  M.fileCount = M.fileCount - 1
  M.globalVersion = M.globalVersion + 1

  M.onWatch('version', uri)
  M.onWatch('remove', uri)
end

--- Get an array containing all file uris
--- @param suri? string
--- @return string[]
function M.getAllUris(suri)
  local scp = suri and scope.getScope(suri) or nil
  local files = {}
  local i = 0
  for uri in pairs(M.fileMap) do
    if not scp or scp:isChildUri(uri) or scp:isLinkedUri(uri) then
      i = i + 1
      files[i] = uri
    end
  end
  table.sort(files)
  return files
end

--- 遍历文件
--- @param suri? string
function M.eachFile(suri)
  local files = M.getAllUris(suri)
  local i = 0
  return function()
    i = i + 1
    local uri = files[i]
    while not M.fileMap[uri] do
      i = i + 1
      uri = files[i]
      if not uri then
        return nil
      end
    end
    return files[i]
  end
end

--- Pairs dll files
function M.eachDll()
  local map = {}
  for uri, file in pairs(M.dllMap) do
    map[uri] = file
  end
  return pairs(map)
end

function M.getLazyCache()
  if not M.lazyCache then
    local cachePath = string.format('%s/cache/%d', LOGPATH, sp.get_id())
    M.lazyCache = cacher(cachePath, log.error)
  end
  return M.lazyCache
end

--- @param state parser.state
--- @param file file
function M.compileStateThen(state, file)
  M.stateTrace[state] = true
  M.stateMap[file.uri] = state
  state.uri = file.uri
  state.lua = file.text
  state.ast.uri = file.uri
  state.diffInfo = file.diffInfo
  state.originLines = file.originLines
  state.originText = file.originText

  local clock = os.clock()
  parser.luadoc(state)
  local passed = os.clock() - clock
  if passed > 0.1 then
    log.warn(
      ('Parse LuaDoc of [%s] takes [%.3f] sec, size [%.3f] kb.'):format(
        file.uri,
        passed,
        #file.text / 1000
      )
    )
  end

  if LAZY and not file.trusted then
    local cache = M.getLazyCache()
    local id = ('%d'):format(file.id)
    clock = os.clock()
    state = lazy.build(state, cache:writterAndReader(id)):entry()
    passed = os.clock() - clock
    if passed > 0.1 then
      log.warn(
        ('Convert lazy-table for [%s] takes [%.3f] sec, size [%.3f] kb.'):format(
          file.uri,
          passed,
          #file.text / 1000
        )
      )
    end
  end

  file.compileCount = file.compileCount + 1
  if file.compileCount >= 3 then
    file.state = state
    log.debug('State persistence:', file.uri)
  end

  M.onWatch('compile', file.uri)
end

--- @param uri string
--- @return boolean
function M.checkPreload(uri)
  local file = M.fileMap[uri]
  if not file then
    return false
  end
  local ws = require('workspace')
  local client = require('client')
  if
    not M.isOpen(uri)
    and not M.isLibrary(uri)
    and #file.text >= config.get(uri, 'Lua.workspace.preloadFileSize') * 1000
  then
    if not M.notifyCache['preloadFileSize'] then
      M.notifyCache['preloadFileSize'] = {}
      M.notifyCache['skipLargeFileCount'] = 0
    end
    if not M.notifyCache['preloadFileSize'][uri] then
      M.notifyCache['preloadFileSize'][uri] = true
      M.notifyCache['skipLargeFileCount'] = M.notifyCache['skipLargeFileCount'] + 1
      local message = lang.script(
        'WORKSPACE_SKIP_LARGE_FILE',
        ws.getRelativePath(uri),
        config.get(uri, 'Lua.workspace.preloadFileSize'),
        #file.text / 1000
      )
      if M.notifyCache['skipLargeFileCount'] <= 1 then
        client.showMessage('Info', message)
      else
        client.logMessage('Info', message)
      end
    end
    return false
  end
  return true
end

--- @param uri string
--- @param callback fun(state: parser.state?)
function M.compileStateAsync(uri, callback)
  local file = M.fileMap[uri]
  if not file then
    callback(nil)
    return
  end
  if M.stateMap[uri] then
    callback(M.stateMap[uri])
    return
  end

  ---@type brave.param.compile.options
  local options = {
    special = config.get(uri, 'Lua.runtime.special'),
    unicodeName = config.get(uri, 'Lua.runtime.unicodeName'),
    nonstandardSymbol = util.arrayToHash(config.get(uri, 'Lua.runtime.nonstandardSymbol')),
  }

  ---@type brave.param.compile
  local params = {
    uri = uri,
    text = file.text,
    mode = 'Lua',
    version = config.get(uri, 'Lua.runtime.version'),
    options = options,
  }
  pub.task('compile', params, function(result)
    if file.text ~= params.text then
      return
    end
    if not result.state then
      log.error('Compile failed:', uri, result.err)
      callback(nil)
      return
    end
    M.compileStateThen(result.state, file)
    callback(result.state)
  end)
end

local function pluginOnTransformAst(uri, state)
  local plugin = require('plugin')
  ---TODO: maybe deepcopy astNode
  local suc, result = plugin.dispatch('OnTransformAst', uri, state.ast)
  if not suc then
    return state
  end
  state.ast = result or state.ast
  return state
end

--- @param uri string
--- @return parser.state?
function M.compileState(uri)
  local file = M.fileMap[uri]
  if not file then
    return
  end
  if M.stateMap[uri] then
    return M.stateMap[uri]
  end
  if not M.checkPreload(uri) then
    return
  end

  ---@type brave.param.compile.options
  local options = {
    special = config.get(uri, 'Lua.runtime.special'),
    unicodeName = config.get(uri, 'Lua.runtime.unicodeName'),
    nonstandardSymbol = util.arrayToHash(config.get(uri, 'Lua.runtime.nonstandardSymbol')),
  }

  local ws = require('workspace')
  local client = require('client')
  if not client.isReady() then
    log.error('Client not ready!', uri)
  end
  local prog <close> = progress.create(uri, lang.script.WINDOW_COMPILING, 0.5)
  prog:setMessage(ws.getRelativePath(uri))
  log.trace('Compile State:', uri)
  local clock = os.clock()
  local state, err =
    parser.compile(file.text, 'Lua', config.get(uri, 'Lua.runtime.version'), options)
  local passed = os.clock() - clock
  if passed > 0.1 then
    log.warn(
      ('Compile [%s] takes [%.3f] sec, size [%.3f] kb.'):format(uri, passed, #file.text / 1000)
    )
  end

  if not state then
    log.error('Compile failed:', uri, err)
    return nil
  end

  state = pluginOnTransformAst(uri, state)
  if not state then
    log.error('pluginOnTransformAst failed! discard the file state')
    return nil
  end

  M.compileStateThen(state, file)

  return state
end

--- @class parser.state
--- @field diffInfo? table[]
--- @field originLines? integer[]
--- @field originText? string
--- @field lua? string

--- Get file syntax tree
--- @param uri string
--- @return parser.state? state
function M.getState(uri)
  local file = M.fileMap[uri]
  if not file then
    return nil
  end
  local state = M.compileState(uri)
  return state
end

--- @param uri string
--- @return parser.state?
function M.getLastState(uri)
  return M.stateMap[uri]
end

function M.getFile(uri)
  return M.fileMap[uri] or M.dllMap[uri]
end

--- Convert the offset before applying the difference to the offset after applying the difference
--- @param state  parser.state
--- @param offset integer
--- @return integer start
--- @return integer finish
function M.diffedOffset(state, offset)
  if not state.diffInfo then
    return offset, offset
  end
  return smerger.getOffset(state.diffInfo, offset)
end

--- Convert the offset after applying the difference to the offset before applying the difference
--- @param state  parser.state
--- @param offset integer
--- @return integer start
--- @return integer finish
function M.diffedOffsetBack(state, offset)
  if not state.diffInfo then
    return offset, offset
  end
  return smerger.getOffsetBack(state.diffInfo, offset)
end

--- @param state parser.state
function M.hasDiffed(state)
  return state.diffInfo ~= nil
end

--- Get the custom cache information of the file (it will automatically expire after the file content is updated)
function M.getCache(uri)
  local file = M.fileMap[uri]
  if not file then
    return nil
  end
  return file.cache
end

--- Get file association
function M.getAssoc(uri)
  local patt = {}
  for k, v in pairs(config.get(uri, 'files.associations')) do
    if v == 'lua' then
      patt[#patt + 1] = k
    end
  end
  M.assocMatcher = glob.glob(patt)
  return M.assocMatcher
end

--- Determine whether it is a Lua file
--- @param uri string
--- @return boolean
function M.isLua(uri)
  if util.stringEndWith(uri:lower(), '.lua') then
    return true
  end
  -- check customed assoc, e.g. `*.lua.txt = *.lua`
  local matcher = M.getAssoc(uri)
  local path = furi.decode(uri)
  return matcher(path)
end

--- Does the uri look like a `Dynamic link library` ?
--- @param uri string
--- @return boolean
function M.isDll(uri)
  local ext = uri:match('%.([^%.%/%\\]+)$')
  if not ext then
    return false
  end
  if platform.os == 'windows' then
    if ext == 'dll' then
      return true
    end
  else
    if ext == 'so' then
      return true
    end
  end
  return false
end

--- Save dll, makes opens and words, discard content
--- @param uri string
--- @param content string
function M.saveDll(uri, content)
  if not content then
    return
  end
  local file = {
    uri = uri,
    opens = {},
    words = {},
  }
  for word in content:gmatch('luaopen_([%w_]+)') do
    file.opens[#file.opens + 1] = word:gsub('_', '.')
  end
  if #file.opens == 0 then
    return
  end
  local mark = {}
  for word in content:gmatch('(%a[%w_]+)\0') do
    if word:sub(1, 3) ~= 'lua' then
      if not mark[word] then
        mark[word] = true
        file.words[#file.words + 1] = word
      end
    end
  end

  M.dllMap[uri] = file
  M.onWatch('dll', uri)
end

--- @param uri string
--- @return string[]|nil
function M.getDllOpens(uri)
  local file = M.dllMap[uri]
  if not file then
    return nil
  end
  return file.opens
end

--- @param uri string
--- @return string[]|nil
function M.getDllWords(uri)
  local file = M.dllMap[uri]
  if not file then
    return nil
  end
  return file.words
end

--- @return integer
function M.countStates()
  local n = 0
  for _ in pairs(M.stateTrace) do
    n = n + 1
  end
  return n
end

--- @param path string
--- @return string
function M.normalize(path)
  path = path:gsub('%$%{(.-)%}', function(key)
    if key == '3rd' then
      return (ROOT / 'meta' / '3rd'):string()
    end
    if key:sub(1, 4) == 'env:' then
      local env = os.getenv(key:sub(5))
      return env
    end
  end)
  path = util.expandPath(path)
  path = path:gsub('^%.[/\\]+', '')
  for _ = 1, 1000 do
    if path:sub(1, 2) == '..' then
      break
    end
    local count
    path, count = path:gsub('[^/\\]+[/\\]+%.%.[/\\]', '/', 1)
    if count == 0 then
      break
    end
  end
  if platform.os == 'windows' then
    path = path:gsub('[/\\]+', '\\'):gsub('[/\\]+$', ''):gsub('^(%a:)$', '%1\\')
  else
    path = path:gsub('[/\\]+', '/'):gsub('[/\\]+$', '')
  end
  return path
end

--- Register event
--- @param callback async fun(ev: string, uri: string)
function M.watch(callback)
  M.watchList[#M.watchList + 1] = callback
end

function M.onWatch(ev, uri)
  for _, callback in ipairs(M.watchList) do
    await.call(function()
      callback(ev, uri)
    end)
  end
end

return M
