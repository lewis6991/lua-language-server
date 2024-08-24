local fsu = require('fs-utility')

local function loadVersion()
    local changelog = fsu.loadFile(ROOT / 'changelog.md')
    if not changelog then
        return
    end

    local version, pos = changelog:match('%#%# (%d+%.%d+%.%d+)()')
    if not version then
        return
    end

    if not changelog:find('^[\r\n]+`', pos) then
        version = version .. '-dev'
    end
    return version
end

local M = {}

function M.getVersion()
    if not M.version then
        M.version = loadVersion() or '<Unknown>'
    end

    return M.version
end

return M
