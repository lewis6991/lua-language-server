local platform = require('bee.platform')
local windows

if platform.os == 'windows' then
  windows = require('bee.windows')
end

local M = {}

function M.toutf8(text)
  if not windows then
    return text
  end
  return windows.a2u(text)
end

function M.fromutf8(text)
  if not windows then
    return text
  end
  return windows.u2a(text)
end

return M
