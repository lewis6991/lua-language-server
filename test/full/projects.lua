local files = require('files')
local fsu = require('fs-utility')
local furi = require('file-uri')
local diag = require('provider.diagnostic')
local config = require('config')
local fs = require('bee.filesystem')

config.set(nil, 'Lua.workspace.preloadFileSize', 1000000)
config.set(nil, 'Lua.diagnostics.neededFileStatus', {
  ['await-in-sync'] = 'Any',
  ['not-yieldable'] = 'Any',
})

---@diagnostic disable: await-in-sync
local function doProjects(pathname)
  local path = fs.path(pathname)
  if not fs.exists(path) then
    return
  end

  local uris = {}

  print('Benchmark diagnostic directory:', path)
  fsu.scanDirectory(path, function(path)
    if path:extension() ~= '.lua' then
      return
    end
    local uri = furi.encode(path:string())
    local text = fsu.loadFile(path)
    files.setText(uri, text)
    files.open(uri)
    uris[#uris + 1] = uri
  end)

  local _ <close> = function()
    for _, uri in ipairs(uris) do
      files.remove(uri)
    end
  end

  print('Start diagnosis...')

  furi.encode(path:string())
  diag.diagnosticsScope(furi.encode(path:string()))

  local clock = os.clock()

  for uri in files.eachFile() do
    local fileClock = os.clock()
    diag.doDiagnostic(uri, true)
    print('Diagnostic file takes time:', os.clock() - fileClock, uri)
  end

  local passed = os.clock() - clock
  print('Benchmark full diagnostic time:', passed)
end

--doProjects [[C:\SSSEditor\client\Output\Lua]]
--doProjects [[C:\W3-Server\script]]
