local tableSort = table.sort
local stringRep = string.rep
local tableConcat = table.concat
local tostring = tostring
local type = type
local pairs = pairs
local ipairs = ipairs
local next = next
local rawset = rawset
local move = table.move
local tableRemove = table.remove
local setmetatable = debug.setmetatable
local mathType = math.type
local mathCeil = math.ceil
local getmetatable = getmetatable
local mathAbs = math.abs
local mathRandom = math.random
local ioOpen = io.open
local utf8Len = utf8.len
local getenv = os.getenv
local getupvalue = debug.getupvalue
local mathHuge = math.huge
local inf = 1 / 0
local nan = 0 / 0
local error = error

_ENV = nil

local function isInteger(n)
    if mathType then
        return mathType(n) == 'integer'
    else
        return type(n) == 'number' and n % 1 == 0
    end
end

local function formatNumber(n)
    -- In the IEEE standard, NAN is not equal to itself. But some
    -- implementations do not follow this rule
    if n == inf or n == -inf or n == nan or n ~= n then
        return ('%q'):format(n)
    end
    if isInteger(n) then
        return tostring(n)
    end
    local str = ('%.10f'):format(n)
    str = str:gsub('%.?0*$', '')
    return str
end

local TAB = setmetatable({}, {
    __index = function(self, n)
        self[n] = stringRep('    ', n)
        return self[n]
    end,
})

local RESERVED = {
    ['and'] = true,
    ['break'] = true,
    ['do'] = true,
    ['else'] = true,
    ['elseif'] = true,
    ['end'] = true,
    ['false'] = true,
    ['for'] = true,
    ['function'] = true,
    ['goto'] = true,
    ['if'] = true,
    ['in'] = true,
    ['local'] = true,
    ['nil'] = true,
    ['not'] = true,
    ['or'] = true,
    ['repeat'] = true,
    ['return'] = true,
    ['then'] = true,
    ['true'] = true,
    ['until'] = true,
    ['while'] = true,
}

local M = {}

---Print table structure
--- @param tbl any
--- @param option? table
--- @return string
function M.dump(tbl, option)
    if not option then
        option = {}
    end
    if type(tbl) ~= 'table' then
        return ('%s'):format(tbl)
    end
    local lines = {}
    local mark = {}
    local stack = {}
    lines[#lines + 1] = '{'
    local function unpack(t)
        local deep = #stack
        mark[t] = (mark[t] or 0) + 1
        local keys = {}
        local keymap = {}
        local integerFormat = '[%d]'
        local alignment = 0
        if #t >= 10 then
            local width = #tostring(#t)
            integerFormat = ('[%%0%dd]'):format(mathCeil(width))
        end
        for key in pairs(t) do
            if type(key) == 'string' then
                if not key:match('^[%a_][%w_]*$') or RESERVED[key] or option['longStringKey'] then
                    keymap[key] = ('[%q]'):format(key)
                else
                    keymap[key] = ('%s'):format(key)
                end
            elseif isInteger(key) then
                keymap[key] = integerFormat:format(key)
            else
                keymap[key] = ('["<%s>"]'):format(tostring(key))
            end
            keys[#keys + 1] = key
            if option['alignment'] then
                if #keymap[key] > alignment then
                    alignment = #keymap[key]
                end
            end
        end
        local mt = getmetatable(t)
        if not mt or not mt.__pairs then
            if option['sorter'] then
                option['sorter'](keys, keymap)
            else
                tableSort(keys, function(a, b)
                    return keymap[a] < keymap[b]
                end)
            end
        end
        for _, key in ipairs(keys) do
            local keyWord = keymap[key]
            if option['noArrayKey'] and isInteger(key) and key <= #t then
                keyWord = ''
            else
                if #keyWord < alignment then
                    keyWord = keyWord .. (' '):rep(alignment - #keyWord) .. ' = '
                else
                    keyWord = keyWord .. ' = '
                end
            end
            local value = t[key]
            local tp = type(value)
            local format = option['format'] and option['format'][key]
            if format then
                value = format(value, unpack, deep + 1, stack)
                tp = type(value)
            end
            if tp == 'table' then
                if mark[value] and mark[value] > 0 then
                    lines[#lines + 1] = ('%s%s%s,'):format(
                        TAB[deep + 1],
                        keyWord,
                        option['loop'] or '"<Loop>"'
                    )
                elseif deep >= (option['deep'] or mathHuge) then
                    lines[#lines + 1] = ('%s%s%s,'):format(TAB[deep + 1], keyWord, '"<Deep>"')
                else
                    lines[#lines + 1] = ('%s%s{'):format(TAB[deep + 1], keyWord)
                    stack[#stack + 1] = key
                    unpack(value)
                    stack[#stack] = nil
                    lines[#lines + 1] = ('%s},'):format(TAB[deep + 1])
                end
            elseif tp == 'string' then
                lines[#lines + 1] = ('%s%s%q,'):format(TAB[deep + 1], keyWord, value)
            elseif tp == 'number' then
                lines[#lines + 1] = ('%s%s%s,'):format(
                    TAB[deep + 1],
                    keyWord,
                    (option['number'] or formatNumber)(value)
                )
            elseif tp == 'nil' then
            else
                lines[#lines + 1] = ('%s%s%s,'):format(TAB[deep + 1], keyWord, tostring(value))
            end
        end
        mark[t] = mark[t] - 1
    end
    unpack(tbl)
    lines[#lines + 1] = '}'
    return tableConcat(lines, '\r\n')
end

--- Recursively determine whether A and B are equal
--- @param valueA any
--- @param valueB any
--- @return boolean
function M.equal(valueA, valueB)
    local hasChecked = {}

    local function equal(a, b)
        local tp1 = type(a)
        local tp2 = type(b)
        if tp1 ~= tp2 then
            return false
        end
        if tp1 == 'table' then
            if hasChecked[a] then
                return true
            end
            hasChecked[a] = true
            local mark = {}
            for k, v in pairs(a) do
                mark[k] = true
                local res = equal(v, b[k])
                if not res then
                    return false
                end
            end
            for k in pairs(b) do
                if not mark[k] then
                    return false
                end
            end
            return true
        elseif tp1 == 'number' then
            if mathAbs(a - b) <= 1e-10 then
                return true
            end
            return tostring(a) == tostring(b)
        else
            return a == b
        end
    end

    return equal(valueA, valueB)
end

local function sortTable(tbl)
    if not tbl then
        tbl = {}
    end
    local mt = {}
    local keys = {}
    local mark = {}
    local n = 0
    for key in next, tbl do
        n = n + 1
        keys[n] = key
        mark[key] = true
    end
    tableSort(keys)
    function mt:__newindex(key, value)
        rawset(self, key, value)
        n = n + 1
        keys[n] = key
        mark[key] = true
        if type(value) == 'table' then
            sortTable(value)
        end
    end
    function mt:__pairs()
        local list = {}
        local m = 0
        for key in next, self do
            if not mark[key] then
                m = m + 1
                list[m] = key
            end
        end
        if m > 0 then
            move(keys, 1, n, m + 1)
            tableSort(list)
            for i = 1, m do
                local key = list[i]
                keys[i] = key
                mark[key] = true
            end
            n = n + m
        end
        local i = 0
        return function()
            i = i + 1
            local key = keys[i]
            return key, self[key]
        end
    end

    return setmetatable(tbl, mt)
end

--- Create an ordered list
--- @param tbl? table
--- @return table
function M.container(tbl)
    return sortTable(tbl)
end

--- Read files
--- @param path string
--- @param keepBom? boolean
--- @return string? text
--- @return string? errMsg
function M.loadFile(path, keepBom)
    local f, e = ioOpen(path, 'rb')
    if not f then
        return nil, e
    end
    local text = f:read('a')
    f:close()
    if not text then
        return nil
    end
    if not keepBom then
        if text:sub(1, 3) == '\xEF\xBB\xBF' then
            return text:sub(4)
        end
        if text:sub(1, 2) == '\xFF\xFE' or text:sub(1, 2) == '\xFE\xFF' then
            return text:sub(3)
        end
    end
    return text
end

--- Write to file
--- @param path string
--- @param content string
--- @return boolean ok
--- @return string? errMsg
function M.saveFile(path, content)
    local f, e = ioOpen(path, 'wb')

    if f then
        f:write(content)
        f:close()
        return true
    else
        return false, e
    end
end

--- Counter
--- @param init? integer
--- @param step? integer
--- @return fun():integer
function M.counter(init, step)
    if not step then
        step = 1
    end
    local current = init and (init - 1) or 0
    return function()
        current = current + step
        return current
    end
end

--- Traverse after sorting
--- @generic K, V
--- @param t table<K, V>
--- @param sorter? fun(a: K, b: K): boolean
--- @return fun(): K, V
function M.sortPairs(t, sorter)
    local keys = {}
    for k in pairs(t) do
        keys[#keys + 1] = k
    end
    tableSort(keys, sorter)
    local i = 0
    return function()
        i = i + 1
        local k = keys[i]
        return k, t[k]
    end
end

--- Deep copy (does not process metatable)
--- @param source  table
--- @param target? table
--- @return table
function M.deepCopy(source, target)
    local mark = {}
    local function copy(a, b)
        if type(a) ~= 'table' then
            return a
        end
        if mark[a] then
            return mark[a]
        end
        if not b then
            b = {}
        end
        mark[a] = b
        for k, v in pairs(a) do
            b[copy(k)] = copy(v)
        end
        return b
    end
    return copy(source, target)
end

--- 序列化
--- @param t table
--- @return table
function M.unpack(t)
    local result = {}
    local tid = 0
    local cache = {}
    local function unpack(o)
        local id = cache[o]
        if not id then
            tid = tid + 1
            id = tid
            cache[o] = tid
            if type(o) == 'table' then
                local new = {}
                result[tid] = new
                for k, v in next, o do
                    new[unpack(k)] = unpack(v)
                end
            else
                result[id] = o
            end
        end
        return id
    end
    unpack(t)
    return result
end

--- 反序列化
--- @param t table
--- @return table
function M.pack(t)
    local cache = {}
    local function pack(id)
        local o = cache[id]
        if o then
            return o
        end
        o = t[id]
        if type(o) == 'table' then
            local new = {}
            cache[id] = new
            for k, v in next, o do
                new[pack(k)] = pack(v)
            end
            return new
        else
            cache[id] = o
            return o
        end
    end
    return pack(1)
end

--- defer
local deferMT = {
    __close = function(self)
        self[1]()
    end,
}
function M.defer(callback)
    return setmetatable({ callback }, deferMT)
end

function M.enableCloseFunction()
    setmetatable(function() end, {
        __close = function(f)
            f()
        end,
    })
end

local esc = {
    ["'"] = [[\']],
    ['"'] = [[\"]],
    ['\r'] = [[\r]],
    ['\n'] = '\\\n',
}

function M.viewString(str, quo)
    if not quo then
        if str:find('[\r\n]') then
            quo = '[['
        elseif not str:find("'", 1, true) and str:find('"', 1, true) then
            quo = "'"
        else
            quo = '"'
        end
    end
    if quo == "'" then
        str = str:gsub('[\000-\008\011-\012\014-\031\127]', function(char)
            return ('\\%03d'):format(char:byte())
        end)
        return quo .. str:gsub([=[['\r\n]]=], esc) .. quo
    elseif quo == '"' then
        str = str:gsub('[\000-\008\011-\012\014-\031\127]', function(char)
            return ('\\%03d'):format(char:byte())
        end)
        return quo .. str:gsub([=[["\r\n]]=], esc) .. quo
    else
        local eqnum = #quo - 2
        local fsymb = ']' .. ('='):rep(eqnum) .. ']'
        if not str:find(fsymb, 1, true) then
            str = str:gsub('[\000-\008\011-\012\014-\031\127]', '')
            return quo .. str .. fsymb
        end
        for i = 0, 10 do
            local fsymb0 = ']' .. ('='):rep(i) .. ']'
            if not str:find(fsymb0, 1, true) then
                local ssymb = '[' .. ('='):rep(i) .. '['
                str = str:gsub('[\000-\008\011-\012\014-\031\127]', '')
                return ssymb .. str .. fsymb0
            end
        end
        return M.viewString(str, '"')
    end
end

function M.viewLiteral(v)
    local tp = type(v)
    if tp == 'nil' then
        return 'nil'
    elseif tp == 'string' then
        return M.viewString(v)
    elseif tp == 'boolean' then
        return tostring(v)
    elseif tp == 'number' then
        if isInteger(v) then
            return tostring(v)
        else
            return formatNumber(v)
        end
    end
    return nil
end

function M.utf8Len(str, start, finish)
    local len = 0
    for _ = 1, 10000 do
        local clen, pos = utf8Len(str, start, finish, true)
        if clen then
            len = len + clen
            break
        else
            len = len + 1 + utf8Len(str, start, pos - 1, true)
            start = pos + 1
        end
    end
    return len
end

--- Reverse the order of elements in the array *in place*
--- @param arr any[]
--- @return any[]
function M.revertArray(arr)
    local len = #arr
    if len <= 1 then
        return arr
    end
    for x = 1, len // 2 do
        local y = len - x + 1
        arr[x], arr[y] = arr[y], arr[x]
    end
    return arr
end

--- Create a value-key table
--- @generic K, V
--- @param t table<K, V>
--- @return table<V, K>
function M.revertMap(t)
    local nt = {}
    for k, v in pairs(t) do
        nt[v] = k
    end
    return nt
end

function M.randomSortTable(t, max)
    local len = #t
    if len <= 1 then
        return t
    end
    if not max or max > len then
        max = len
    end
    for x = 1, max do
        local y = mathRandom(len)
        t[x], t[y] = t[y], t[x]
    end
    return t
end

function M.tableMultiRemove(t, index)
    local mark = {}
    for i = 1, #index do
        local v = index[i]
        mark[v] = true
    end
    local offset = 0
    local me = 1
    local len = #t
    while true do
        local it = me + offset
        if it > len then
            for i = me, len do
                t[i] = nil
            end
            break
        end
        if mark[it] then
            offset = offset + 1
        else
            if me ~= it then
                t[me] = t[it]
            end
            me = me + 1
        end
    end
end

--- Traverse each line of text
--- @param text string
--- @param keepNL? boolean Keep newlines
--- @return fun():string?, integer?
function M.eachLine(text, keepNL)
    local offset = 1
    local lineCount = 0
    local lastLine
    return function()
        lineCount = lineCount + 1
        if offset > #text then
            if not lastLine then
                lastLine = ''
                return '', lineCount
            end
            return nil
        end
        local nl = text:find('[\r\n]', offset)
        if not nl then
            lastLine = text:sub(offset)
            offset = #text + 1
            return lastLine, lineCount
        end
        local line
        if text:sub(nl, nl + 1) == '\r\n' then
            if keepNL then
                line = text:sub(offset, nl + 1)
            else
                line = text:sub(offset, nl - 1)
            end
            offset = nl + 2
        else
            if keepNL then
                line = text:sub(offset, nl)
            else
                line = text:sub(offset, nl - 1)
            end
            offset = nl + 1
        end
        return line, lineCount
    end
end

--- @alias SortByScoreCallback fun(o: any): integer

--- Sort by score, the higher the score, the higher it is
--- @param tbl any[]
--- @param callbacks SortByScoreCallback | SortByScoreCallback[]
function M.sortByScore(tbl, callbacks)
    if type(callbacks) ~= 'table' then
        callbacks = { callbacks }
    end
    local size = #callbacks
    local scoreCache = {}
    for i = 1, size do
        scoreCache[i] = {}
    end
    tableSort(tbl, function(a, b)
        for i = 1, size do
            local callback = callbacks[i]
            local cache = scoreCache[i]
            local sa = cache[a] or callback(a)
            local sb = cache[b] or callback(b)
            cache[a] = sa
            cache[b] = sb
            if sa > sb then
                return true
            elseif sa < sb then
                return false
            end
        end
        return false
    end)
end

--- @param arr any[]
--- @return SortByScoreCallback
function M.sortCallbackOfIndex(arr)
    ---@type table<any, integer>
    local indexMap = M.revertMap(arr)
    return function(v)
        return -indexMap[v]
    end
end

--- @param datas any[]
--- @param scores integer[]
--- @return SortByScoreCallback
function M.sortCallbackOfScore(datas, scores)
    local map = {}
    for i = 1, #datas do
        local data = datas[i]
        local score = scores[i]
        map[data] = score
    end
    return function(v)
        return map[v]
    end
end

--- Cut the string
--- @param str string
--- @param mode? '"left"'|'"right"'
--- @return string
function M.trim(str, mode)
    if mode == 'left' then
        return (str:gsub('^%s+', ''))
    end
    if mode == 'right' then
        return (str:gsub('%s+$', ''))
    end
    return (str:match('^%s*(.-)%s*$'))
end

function M.expandPath(path)
    if path:sub(1, 1) == '~' then
        local home = getenv('HOME')
        if not home then -- has to be Windows
            home = getenv('USERPROFILE') or (getenv('HOMEDRIVE') .. getenv('HOMEPATH'))
        end
        return home .. path:sub(2)
    elseif path:sub(1, 1) == '$' then
        path = path:gsub('%$([%w_]+)', getenv)
        return path
    end
    return path
end

function M.arrayToHash(l)
    local t = {}
    for i = 1, #l do
        t[l[i]] = true
    end
    return t
end

--- @class switch
--- @field cachedCases string[]
--- @field map table<string, function>
--- @field _default fun(...):...
local switchMT = {}
switchMT.__index = switchMT

--- @param name string
--- @return switch
function switchMT:case(name)
    self.cachedCases[#self.cachedCases + 1] = name
    return self
end

--- @param callback async fun(...):...
--- @return switch
function switchMT:call(callback)
    for i = 1, #self.cachedCases do
        local name = self.cachedCases[i]
        self.cachedCases[i] = nil
        if self.map[name] then
            error('Repeated fields:' .. tostring(name))
        end
        self.map[name] = callback
    end
    return self
end

--- @param callback fun(...):...
--- @return switch
function switchMT:default(callback)
    self._default = callback
    return self
end

function switchMT:getMap()
    return self.map
end

--- @param name string
--- @return boolean
function switchMT:has(name)
    return self.map[name] ~= nil
end

--- @param name string
--- @param ... any
--- @return ...
function switchMT:__call(name, ...)
    local callback = self.map[name] or self._default
    if not callback then
        return
    end
    return callback(...)
end

--- @return switch
function M.switch()
    local obj = setmetatable({
        map = {},
        cachedCases = {},
    }, switchMT)
    return obj
end

--- @param t table<string|string[],function>
--- @return fun(ty: string): function
function M.switch2(t)
    return function(ty)
        -- Defer table expansion until first miss
        if not t[ty] then
            local expanded = {}
            for k, v in pairs(t) do
                if type(k) == 'table' then
                    for _, k2 in pairs(k) do
                        expanded[k2] = v
                    end
                else
                    expanded[k] = v
                end
            end
            t = expanded
        end
        return t[ty] or function(...) end
    end
end

--- @param f async fun()
--- @param name string
--- @return any, boolean
function M.getUpvalue(f, name)
    for i = 1, 999 do
        local uname, value = getupvalue(f, i)
        if not uname then
            break
        end
        if name == uname then
            return value, true
        end
    end
    return nil, false
end

function M.stringStartWith(str, head)
    return str:sub(1, #head) == head
end

function M.stringEndWith(str, tail)
    return str:sub(-#tail) == tail
end

function M.defaultTable(default)
    return setmetatable({}, {
        __index = function(t, k)
            if k == nil then
                return nil
            end
            local v = default(k)
            t[k] = v
            return v
        end,
    })
end

function M.multiTable(count, default)
    local current
    if default then
        current = setmetatable({}, {
            __index = function(t, k)
                if k == nil then
                    return nil
                end
                local v = default(k)
                t[k] = v
                return v
            end,
        })
    else
        current = setmetatable({}, {
            __index = function(t, k)
                if k == nil then
                    return nil
                end
                local v = {}
                t[k] = v
                return v
            end,
        })
    end
    for _ = 3, count do
        local tt = current
        current = setmetatable({}, {
            __index = function(t, k)
                if k == nil then
                    return nil
                end
                t[k] = tt
                return tt
            end,
        })
    end
    return current
end

--- @param t table
--- @param sorter boolean|function
--- @return any[]
function M.getTableKeys(t, sorter)
    local keys = {}
    for k in pairs(t) do
        keys[#keys + 1] = k
    end
    if sorter == true then
        tableSort(keys)
    elseif type(sorter) == 'function' then
        tableSort(keys, sorter)
    end
    return keys
end

function M.arrayHas(array, value)
    for i = 1, #array do
        if array[i] == value then
            return true
        end
    end
    return false
end

function M.arrayIndexOf(array, value)
    for i = 1, #array do
        if array[i] == value then
            return i
        end
    end
    return nil
end

function M.arrayInsert(array, value)
    if not M.arrayHas(array, value) then
        array[#array + 1] = value
    end
end

function M.arrayRemove(array, value)
    for i = 1, #array do
        if array[i] == value then
            tableRemove(array, i)
            return
        end
    end
end

M.MODE_K = { __mode = 'k' }
M.MODE_V = { __mode = 'v' }
M.MODE_KV = { __mode = 'kv' }

--- @generic T: fun(param: any):any
--- @param func T
--- @return T
function M.cacheReturn(func)
    local cache = {}
    return function(param)
        if cache[param] == nil then
            cache[param] = func(param)
        end
        return cache[param]
    end
end

--- @param a table
--- @param b table
--- @return table
function M.tableMerge(a, b)
    for k, v in pairs(b) do
        a[k] = v
    end
    return a
end

--- @param a any[]
--- @param b any[]
--- @return any[]
function M.arrayMerge(a, b)
    for i = 1, #b do
        a[#a + 1] = b[i]
    end
    return a
end

return M
