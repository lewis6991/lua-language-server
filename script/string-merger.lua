--- @class string.merger.diff
--- @field start integer Replace the starting byte
--- @field finish integer Replace the ending byte
--- @field text string Replacement text

--- @class string.merger.info: string.merger.diff
--- @field cstart integer Converted start byte
--- @field cfinish integer Converted end byte

--- @alias string.merger.diffs string.merger.diff[]
--- @alias string.merger.infos string.merger.info[]

--- Find the nearest starting position based on the bisection method
--- @param diffs  table
--- @param offset any
--- @return string.merger.info
local function getNearDiff(diffs, offset, key)
    local min = 1
    local max = #diffs
    while max > min do
        local middle = min + (max - min) // 2
        local diff = diffs[middle]
        local ndiff = diffs[middle + 1]
        if diff[key] > offset then
            max = middle
            goto CONTINUE
        end
        if not ndiff then
            return diff
        end
        if ndiff[key] > offset then
            return diff
        end
        if min == middle then
            min = middle + 1
        else
            min = middle
        end
        ::CONTINUE::
    end
    return diffs[min]
end

local M = {}

--- Merge text with differences
--- @param text  string
--- @param diffs string.merger.diffs
--- @return string
--- @return string.merger.infos
function M.mergeDiff(text, diffs)
    local info = {}
    for i, diff in ipairs(diffs) do
        info[i] = {
            start = diff.start,
            finish = diff.finish,
            text = diff.text,
        }
    end
    table.sort(info, function(a, b)
        return a.start < b.start
    end)
    local cur = 1
    local buf = {}
    local delta = 0
    for _, diff in ipairs(info) do
        diff.cstart = diff.start + delta
        diff.cfinish = diff.cstart + #diff.text - 1
        buf[#buf + 1] = text:sub(cur, diff.start - 1)
        buf[#buf + 1] = diff.text
        cur = diff.finish + 1
        delta = delta + #diff.text - (diff.finish - diff.start + 1)
    end
    buf[#buf + 1] = text:sub(cur)
    return table.concat(buf), info
end

--- Get the converted position based on the position before conversion
--- @param info   string.merger.infos
--- @param offset integer
--- @return integer start
--- @return integer finish
function M.getOffset(info, offset)
    local diff = getNearDiff(info, offset, 'start')
    if not diff then
        return offset, offset
    end
    if offset <= diff.finish then
        local start, finish
        if offset == diff.start then
            start = diff.cstart
        end
        if offset == diff.finish then
            finish = diff.cfinish
        end
        if not start or not finish then
            local soff = offset - diff.start
            local pos = math.min(diff.cstart + soff, diff.cfinish)
            start = start or pos
            finish = finish or pos
        end
        if start > finish then
            start = finish
        end
        return start, finish
    end
    local pos = offset - diff.finish + diff.cfinish
    return pos, pos
end

--- Get the position before conversion based on the converted position
--- @param info   string.merger.infos
--- @param offset integer
--- @return integer start
--- @return integer finish
function M.getOffsetBack(info, offset)
    local diff = getNearDiff(info, offset, 'cstart')
    if not diff then
        return offset, offset
    end
    if offset <= diff.cfinish then
        local start, finish
        if offset == diff.cstart then
            start = diff.start
        end
        if offset == diff.cfinish then
            finish = diff.finish
        end
        if not start or not finish then
            if offset > diff.cstart and offset < diff.cfinish then
                return diff.finish, diff.finish
            end
            local soff = offset - diff.cstart
            local pos = math.min(diff.start + soff, diff.finish)
            start = start or pos
            finish = finish or pos
        end
        if start > finish then
            start = finish
        end
        return start, finish
    end
    local pos = offset - diff.cfinish + diff.finish
    return pos, pos
end

return M
