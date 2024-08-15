local suc, codeFormat = pcall(require, 'code_format')
if not suc then
  return
end

local config = require('config')

local M = {}

M.loaded = false

function M.nameStyleCheck(uri, text)
  if not M.loaded then
    local value = config.get(nil, 'Lua.nameStyle.config')
    codeFormat.update_name_style_config(value)
    M.loaded = true
  end

  return codeFormat.name_style_analysis(uri, text)
end

config.watch(function(_uri, key, value)
  if key == 'Lua.nameStyle.config' then
    codeFormat.update_name_style_config(value)
  end
end)

return M
