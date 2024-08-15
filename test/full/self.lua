local files = require('files')
local fsu = require('fs-utility')
local furi = require('file-uri')
local diag = require('provider.diagnostic')
local ws = require('workspace')
local guide = require('parser.guide')
local vm = require('vm')
local util = require('utility')

local path = ROOT / 'script'

local uris = {}

files.reset()
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

print('Benchmark diagnostic directory:', path)

ws.awaitReady(furi.encode(path:string()))
diag.diagnosticsScope(furi.encode(path:string()))

local clock = os.clock()

---@diagnostic disable: await-in-sync
for uri in files.eachFile() do
  local state = files.getState(uri)
  if state then
    guide.eachSource(state.ast, function(src)
      assert(src.parent ~= nil or src.type == 'main')
    end)
    local fileClock = os.clock()
    diag.doDiagnostic(uri, true)
    print('Diagnostic file takes time:', os.clock() - fileClock, uri)
  end
end

do
  local passed = os.clock() - clock
  print('Benchmark full diagnostic time:', passed)
end

vm.clearNodeCache()

clock = os.clock()
local compileDatas = {}

for uri in files.eachFile() do
  local state = files.getState(uri)
  if state then
    clock = os.clock()
    guide.eachSource(state.ast, function(src)
      vm.compileNode(src)
    end)
    compileDatas[uri] = {
      passed = os.clock() - clock,
      uri = uri,
    }
  end
end

local printTexts = {}
for uri, data in
  util.sortPairs(compileDatas, function(a, b)
    return compileDatas[a].passed > compileDatas[b].passed
  end)
do
  printTexts[#printTexts + 1] = ('Full compilation time: %05.3f [%s]'):format(data.passed, uri)
  if #printTexts >= 10 then
    break
  end
end

util.revertArray(printTexts)

for _, text in ipairs(printTexts) do
  print(text)
end

local passed = os.clock() - clock
print('Benchmark full compilation time:', passed)
