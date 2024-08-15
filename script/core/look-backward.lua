--- @class lookForward
local M = {}

--- Is it a whitespace character?
--- @param char    string
--- @param inline? boolean # Must be on the same line (excluding newlines)
function M.isSpace(char, inline)
  if inline then
    if char == ' ' or char == '\t' then
      return true
    end
  else
    if char == ' ' or char == '\n' or char == '\r' or char == '\t' then
      return true
    end
  end
  return false
end

--- Skip whitespace characters
--- @param text    string
--- @param offset  integer
--- @param inline? boolean # Must be on the same line (excluding newlines)
function M.skipSpace(text, offset, inline)
  for i = offset, 1, -1 do
    local char = text:sub(i, i)
    if not M.isSpace(char, inline) then
      return i
    end
  end
  return 0
end

function M.findWord(text, offset)
  for i = offset, 1, -1 do
    if not text:sub(i, i):match('[%w_\x80-\xff]') then
      if i == offset then
        return nil
      end
      return text:sub(i + 1, offset), i + 1
    end
  end
  return text:sub(1, offset), 1
end

function M.findSymbol(text, offset)
  for i = offset, 1, -1 do
    local char = text:sub(i, i)
    if not M.isSpace(char) then
      if
        char == '.'
        or char == ':'
        or char == '('
        or char == ','
        or char == '['
        or char == '='
        or char == '{'
      then
        return char, i
      end
      return nil
    end
  end
end

function M.findTargetSymbol(text, offset, symbol)
  offset = M.skipSpace(text, offset)
  for i = offset, 1, -1 do
    local char = text:sub(i - #symbol + 1, i)
    if char == symbol then
      return i - #symbol + 1
    end
    return
  end
end

--- @param text string
--- @param offset integer
--- @param inline? boolean # Must be on the same line (excluding newlines)
function M.findAnyOffset(text, offset, inline)
  for i = offset, 1, -1 do
    local c = text:sub(i, i)
    if inline then
      if c == '\r' or c == '\n' then
        return nil
      end
    end
    if not M.isSpace(c) then
      return i
    end
  end
end

return M
