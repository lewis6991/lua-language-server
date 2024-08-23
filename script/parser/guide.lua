--- @class parser.object
--- @field bindDocs              parser.object[]
--- @field bindGroup             parser.object[]
--- @field bindSource            parser.object
--- @field value                 parser.object
--- @field parent                parser.object
--- @field type                  string
--- @field special               string
--- @field tag                   string
--- @field args                  { [integer]: parser.object, start: integer, finish: integer, type: string }
--- @field locals                parser.object[]
--- @field returns?              parser.object[]
--- @field breaks?               parser.object[]
--- @field exps                  parser.object[]
--- @field keys                  parser.object
--- @field uri                   string
--- @field start                 integer
--- @field finish                integer
--- @field range                 integer
--- @field effect                integer
--- @field bstart                integer
--- @field bfinish               integer
--- @field attrs                 string[]
--- @field specials              parser.object[]
--- @field labels                parser.object[]
--- @field node                  parser.object
--- @field field                 parser.object
--- @field method                parser.object
--- @field index                 parser.object
--- @field extends               parser.object[]|parser.object
--- @field types                 parser.object[]
--- @field fields                parser.object[]
--- @field tkey                  parser.object
--- @field tvalue                parser.object
--- @field tindex                integer
--- @field op                    parser.object
--- @field next                  parser.object
--- @field docParam              parser.object
--- @field sindex                integer
--- @field name                  parser.object
--- @field call                  parser.object
--- @field closure               parser.object
--- @field proto                 parser.object
--- @field exp                   parser.object
--- @field alias                 parser.object
--- @field class                 parser.object
--- @field enum                  parser.object
--- @field vararg                parser.object
--- @field param                 parser.object
--- @field overload              parser.object
--- @field docParamMap           table<string, integer>
--- @field upvalues              table<string, string[]>
--- @field ref                   parser.object[]
--- @field returnIndex           integer
--- @field assignIndex           integer
--- @field docIndex              integer
--- @field docs                  parser.object
--- @field state                 table
--- @field comment               table
--- @field optional              boolean
--- @field max                   parser.object
--- @field init                  parser.object
--- @field step                  parser.object
--- @field redundant             { max: integer, passed: integer }
--- @field filter                parser.object
--- @field loc                   parser.object
--- @field keyword               integer[]
--- @field casts                 parser.object[]
--- @field mode?                 '+' | '-'
--- @field hasGoTo?              true
--- @field hasReturn?            true
--- @field hasBreak?             true
--- @field hasExit?              true
--- @field [integer]             parser.object|any
--- @field dot                   { type: string, start: integer, finish: integer }
--- @field colon                 { type: string, start: integer, finish: integer }
--- @field package _root         parser.object
--- @field package _eachCache?   parser.object[]
--- @field package _isGlobal?    boolean
--- @field package _typeCache?   parser.object[][]

--- @class guide
--- @field debugMode boolean
local M = {}

M.ANY = { '<ANY>' }

M.notNamePattern = '[^%w_\x80-\xff]'
M.namePattern = '[%a_\x80-\xff][%w_\x80-\xff]*'
M.namePatternFull = '^' .. M.namePattern .. '$'

local blockTypes = {
    ['while'] = true,
    ['in'] = true,
    ['loop'] = true,
    ['repeat'] = true,
    ['do'] = true,
    ['function'] = true,
    ['if'] = true,
    ['ifblock'] = true,
    ['elseblock'] = true,
    ['elseifblock'] = true,
    ['main'] = true,
}

M.blockTypes = blockTypes

local topBlockTypes = {
    ['while'] = true,
    ['function'] = true,
    ['if'] = true,
    ['ifblock'] = true,
    ['elseblock'] = true,
    ['elseifblock'] = true,
    ['main'] = true,
}

local breakBlockTypes = {
    ['while'] = true,
    ['in'] = true,
    ['loop'] = true,
    ['repeat'] = true,
    ['for'] = true,
}

local childMap = {
    ['main'] = { '#', 'docs' },
    ['repeat'] = { '#', 'filter' },
    ['while'] = { 'filter', '#' },
    ['in'] = { 'keys', 'exps', '#' },
    ['loop'] = { 'loc', 'init', 'max', 'step', '#' },
    ['do'] = { '#' },
    ['if'] = { '#' },
    ['ifblock'] = { 'filter', '#' },
    ['elseifblock'] = { 'filter', '#' },
    ['elseblock'] = { '#' },
    ['setfield'] = { 'node', 'field', 'value' },
    ['getfield'] = { 'node', 'field' },
    ['setmethod'] = { 'node', 'method', 'value' },
    ['getmethod'] = { 'node', 'method' },
    ['setindex'] = { 'node', 'index', 'value' },
    ['getindex'] = { 'node', 'index' },
    ['tableindex'] = { 'index', 'value' },
    ['tablefield'] = { 'field', 'value' },
    ['tableexp'] = { 'value' },
    ['setglobal'] = { 'value' },
    ['local'] = { 'attrs', 'value' },
    ['setlocal'] = { 'value' },
    ['return'] = { '#' },
    ['select'] = { 'vararg' },
    ['table'] = { '#' },
    ['function'] = { 'args', '#' },
    ['funcargs'] = { '#' },
    ['paren'] = { 'exp' },
    ['call'] = { 'node', 'args' },
    ['callargs'] = { '#' },
    ['list'] = { '#' },
    ['binary'] = { 1, 2 },
    ['unary'] = { 1 },

    ['doc'] = { '#' },
    ['doc.class'] = { 'class', '#extends', '#signs', 'docAttr', 'comment' },
    ['doc.type'] = { '#types', 'name', 'comment' },
    ['doc.alias'] = { 'alias', 'docAttr', 'extends', 'comment' },
    ['doc.enum'] = { 'enum', 'extends', 'comment', 'docAttr' },
    ['doc.param'] = { 'param', 'extends', 'comment' },
    ['doc.return'] = { '#returns', 'comment' },
    ['doc.field'] = { 'field', 'extends', 'comment' },
    ['doc.generic'] = { '#generics', 'comment' },
    ['doc.generic.object'] = { 'generic', 'extends', 'comment' },
    ['doc.vararg'] = { 'vararg', 'comment' },
    ['doc.type.array'] = { 'node' },
    ['doc.type.function'] = { '#args', '#returns', 'comment' },
    ['doc.type.table'] = { '#fields', 'comment' },
    ['doc.type.literal'] = { 'node' },
    ['doc.type.arg'] = { 'name', 'extends' },
    ['doc.type.field'] = { 'name', 'extends' },
    ['doc.type.sign'] = { 'node', '#signs' },
    ['doc.overload'] = { 'overload', 'comment' },
    ['doc.see'] = { 'name', 'comment' },
    ['doc.version'] = { '#versions' },
    ['doc.diagnostic'] = { '#names' },
    ['doc.as'] = { 'as' },
    ['doc.cast'] = { 'name', '#casts' },
    ['doc.cast.block'] = { 'extends' },
    ['doc.operator'] = { 'op', 'exp', 'extends' },
    ['doc.meta'] = { 'name' },
    ['doc.attr'] = { '#names' },
}

--- @type table<string, fun(obj: parser.object, list: parser.object[])>
local compiledChildMap = setmetatable({}, {
    __index = function(self, name)
        local defs = childMap[name]
        if not defs then
            self[name] = false
            return false
        end
        local text = {}
        text[#text + 1] = 'local obj, list = ...'
        for _, def in ipairs(defs) do
            if def == '#' then
                text[#text + 1] = [[
for i = 1, #obj do
    list[#list+1] = obj[i]
end
]]
            elseif type(def) == 'string' and def:sub(1, 1) == '#' then
                local key = def:sub(2)
                text[#text + 1] = ([[
local childs = obj.%s
if childs then
    for i = 1, #childs do
        list[#list+1] = childs[i]
    end
end
]]):format(key)
            elseif type(def) == 'string' then
                text[#text + 1] = ('list[#list+1] = obj.%s'):format(def)
            else
                text[#text + 1] = ('list[#list+1] = obj[%q]'):format(def)
            end
        end
        local buf = table.concat(text, '\n')
        local f = load(buf, buf, 't')
        self[name] = f
        return f
    end,
})

local eachChildMap = setmetatable({}, {
    __index = function(self, name)
        local defs = childMap[name]
        if not defs then
            self[name] = false
            return false
        end
        local text = {}
        text[#text + 1] = 'local obj, callback = ...'
        for _, def in ipairs(defs) do
            if def == '#' then
                text[#text + 1] = [[
for i = 1, #obj do
    callback(obj[i])
end
]]
            elseif type(def) == 'string' and def:sub(1, 1) == '#' then
                local key = def:sub(2)
                text[#text + 1] = ([[
local childs = obj.%s
if childs then
    for i = 1, #childs do
        callback(childs[i])
    end
end
]]):format(key)
            elseif type(def) == 'string' then
                text[#text + 1] = ('callback(obj.%s)'):format(def)
            else
                text[#text + 1] = ('callback(obj[%q])'):format(def)
            end
        end
        local buf = table.concat(text, '\n')
        local f = load(buf, buf, 't')
        self[name] = f
        return f
    end,
})

M.actionMap = {
    ['main'] = { '#' },
    ['repeat'] = { '#' },
    ['while'] = { '#' },
    ['in'] = { '#' },
    ['loop'] = { '#' },
    ['if'] = { '#' },
    ['ifblock'] = { '#' },
    ['elseifblock'] = { '#' },
    ['elseblock'] = { '#' },
    ['do'] = { '#' },
    ['function'] = { '#' },
    ['funcargs'] = { '#' },
}

--- Whether it is a literal
--- @param obj table
--- @return boolean
function M.isLiteral(obj)
    local tp = obj.type
    return tp == 'nil'
        or tp == 'boolean'
        or tp == 'string'
        or tp == 'number'
        or tp == 'integer'
        or tp == 'table'
        or tp == 'function'
        or tp == 'doc.type.function'
        or tp == 'doc.type.table'
        or tp == 'doc.type.string'
        or tp == 'doc.type.integer'
        or tp == 'doc.type.boolean'
        or tp == 'doc.type.code'
        or tp == 'doc.type.array'
end

--- Get the literal
--- @param obj table
--- @return any
function M.getLiteral(obj)
    if M.isLiteral(obj) then
        return obj[1]
    end
end

--- Find the parent function
--- @param obj parser.object
--- @return parser.object?
function M.getParentFunction(obj)
    for _ = 1, 10000 do
        obj = obj.parent
        if not obj then
            break
        end
        local tp = obj.type
        if tp == 'function' or tp == 'main' then
            return obj
        end
    end
end

--- Find the block
--- @param obj parser.object.union
--- @return parser.object.block?
function M.getBlock(obj)
    for _ = 1, 10000 do
        if not obj then
            return
        end
        local tp = obj.type
        if blockTypes[tp] then
            --- @cast obj parser.object.block
            return obj
        end
        if obj == obj.parent then
            error('obj == obj.parent?' .. obj.type)
        end
        obj = obj.parent
    end

    --- @cast obj -?

    -- make stack
    local stack = {} --- @type string[]
    for _ = 1, 10 do
        stack[#stack + 1] = ('%s:%s'):format(obj.type, obj.finish)
        obj = obj.parent
        if not obj then
            break
        end
    end
    error('guide.getBlock overstack:' .. table.concat(stack, ' -> '))
end

--- Find the parent block
--- @param obj parser.object.union
--- @return parser.object.block?
function M.getParentBlock(obj)
    for _ = 1, 10000 do
        obj = obj.parent
        if not obj then
            return
        end
        local tp = obj.type
        if blockTypes[tp] then
            return obj
        end
    end
    error('guide.getParentBlock overstack')
end

--- Find the parent block that can be broken
--- @param obj parser.object
--- @return parser.object?
function M.getBreakBlock(obj)
    for _ = 1, 10000 do
        obj = obj.parent
        if not obj then
            return
        end
        local tp = obj.type
        if breakBlockTypes[tp] then
            return obj
        end
        if tp == 'function' then
            return
        end
    end
    error('guide.getBreakBlock overstack')
end

--- Find the body of the doc
--- @param obj parser.object
--- @return parser.object
function M.getDocState(obj)
    for _ = 1, 10000 do
        local parent = obj.parent
        if not parent then
            return obj
        end
        if parent.type == 'doc' then
            return obj
        end
        obj = parent
    end
    error('guide.getDocState overstack')
end

--- Find the parent type
--- @param obj parser.object
--- @return parser.object?
function M.getParentType(obj, want)
    for _ = 1, 10000 do
        obj = obj.parent
        if not obj then
            return
        end
        if want == obj.type then
            return obj
        end
    end
    error('guide.getParentType overstack')
end

--- Find the parent type
--- @param obj parser.object
--- @return parser.object?
function M.getParentTypes(obj, wants)
    for _ = 1, 10000 do
        obj = obj.parent
        if not obj then
            return
        end
        if wants[obj.type] then
            return obj
        end
    end
    error('guide.getParentTypes overstack')
end

--- Find the root block
--- @param obj parser.object
--- @return parser.object
function M.getRoot(obj)
    local source = obj
    if source._root then
        return source._root
    end
    for _ = 1, 10000 do
        if obj.type == 'main' then
            source._root = obj
            return obj
        end
        if obj._root then
            source._root = obj._root
            return source._root
        end
        local parent = obj.parent
        if not parent then
            error('Can not find out root:' .. tostring(obj.type))
        end
        obj = parent
    end
    error('guide.getRoot overstack')
end

--- @param obj parser.object | { uri: string }
--- @return string
function M.getUri(obj)
    if obj.uri then
        return obj.uri
    end
    local root = M.getRoot(obj)
    if root then
        return root.uri or ''
    end
    return ''
end

--- @return parser.object?
function M.getENV(source, start)
    if not start then
        start = 1
    end
    return M.getLocal(source, '_ENV', start) or M.getLocal(source, '@fenv', start)
end

--- Get the local variables visible in the specified block
--- @param source parser.object
--- @param name string # variable name
--- @param pos integer # Visible position
--- @return parser.object?
function M.getLocal(source, name, pos)
    local block = source
    -- find nearest source
    for _ = 1, 10000 do
        if not block then
            return
        end
        if block.type == 'main' then
            break
        end
        if block.start <= pos and block.finish >= pos and blockTypes[block.type] then
            break
        end
        block = block.parent
    end

    M.eachSourceContain(block, pos, function(src)
        if blockTypes[src.type] and (src.finish - src.start) < (block.finish - src.start) then
            block = src
        end
    end)

    for _ = 1, 10000 do
        if not block then
            break
        end
        local res
        if block.locals then
            for _, loc in ipairs(block.locals) do
                if loc[1] == name and loc.effect <= pos then
                    if not res or res.effect < loc.effect then
                        res = loc
                    end
                end
            end
        end
        if res then
            return res
        end
        block = block.parent
    end
end

--- Get all visible local variable names in the specified block
function M.getVisibleLocals(block, pos)
    local result = {}
    M.eachSourceContain(M.getRoot(block), pos, function(source)
        local locals = source.locals
        if locals then
            for i = 1, #locals do
                local loc = locals[i]
                local name = loc[1]
                if loc.effect <= pos then
                    result[name] = loc
                end
            end
        end
    end)
    return result
end

--- Get the visible tags in the specified block
--- @param block parser.object.block
--- @param name string
--- @return parser.object.label?
function M.getLabel(block, name)
    local current = M.getBlock(block)
    for _ = 1, 10000 do
        if not current then
            return
        end
        local labels = current.labels
        if labels then
            local label = labels[name]
            if label then
                return label
            end
        end
        if current.type == 'function' then
            return
        end
        current = M.getParentBlock(current)
    end
    error('guide.getLocal overstack')
end

function M.getStartFinish(source)
    local start = source.start
    local finish = source.finish
    if source.bfinish and source.bfinish > finish then
        finish = source.bfinish
    end
    if not start then
        local first = source[1]
        if not first then
            return
        end
        local last = source[#source]
        start = first.start
        finish = last.finish
    end
    return start, finish
end

function M.getRange(source)
    local start = source.vstart or source.start
    local finish = source.range or source.finish
    if source.bfinish and source.bfinish > finish then
        finish = source.bfinish
    end
    if not start then
        local first = source[1]
        if not first then
            return
        end
        local last = source[#source]
        start = first.vstart or first.start
        finish = last.range or last.finish
    end
    return start, finish
end

--- Determine whether source contains position
function M.isContain(source, position)
    local start, finish = M.getStartFinish(source)
    if not start then
        return false
    end
    return start <= position and finish >= position
end

--- Determine whether the position is within the scope of influence of the source
---
--- Mainly for assignment and other statements, key contains value
function M.isInRange(source, position)
    local start, finish = M.getRange(source)
    if not start then
        return false
    end
    return start <= position and finish >= position
end

function M.isBetween(source, tStart, tFinish)
    local start, finish = M.getStartFinish(source)
    if not start then
        return false
    end
    return start <= tFinish and finish >= tStart
end

function M.isBetweenRange(source, tStart, tFinish)
    local start, finish = M.getRange(source)
    if not start then
        return false
    end
    return start <= tFinish and finish >= tStart
end

--- Add child
local function addChilds(list, obj)
    local tp = obj.type
    if not tp then
        return
    end
    local f = compiledChildMap[tp]
    if not f then
        return
    end
    f(obj, list)
end

--- Traverse all sources containing position
--- @param ast parser.object
--- @param position integer
--- @param callback fun(src: parser.object): any
function M.eachSourceContain(ast, position, callback)
    local list = { ast }
    local mark = {}
    while true do
        local len = #list
        if len == 0 then
            return
        end
        local obj = list[len]
        list[len] = nil
        if not mark[obj] then
            mark[obj] = true
            if M.isInRange(obj, position) then
                if M.isContain(obj, position) then
                    local res = callback(obj)
                    if res ~= nil then
                        return res
                    end
                end
                addChilds(list, obj)
            end
        end
    end
end

--- Traverse all sources within a certain range
function M.eachSourceBetween(ast, start, finish, callback)
    local list = { ast }
    local mark = {}
    while true do
        local len = #list
        if len == 0 then
            return
        end
        local obj = list[len]
        list[len] = nil
        if not mark[obj] then
            mark[obj] = true
            if M.isBetweenRange(obj, start, finish) then
                if M.isBetween(obj, start, finish) then
                    local res = callback(obj)
                    if res ~= nil then
                        return res
                    end
                end
                addChilds(list, obj)
            end
        end
    end
end

local function getSourceTypeCache(ast)
    local cache = ast._typeCache
    if not cache then
        cache = {}
        ast._typeCache = cache
        M.eachSource(ast, function(source)
            local tp = source.type
            if not tp then
                return
            end
            local myCache = cache[tp]
            if not myCache then
                myCache = {}
                cache[tp] = myCache
            end
            myCache[#myCache + 1] = source
        end)
    end
    return cache
end

--- Traverse all sources of the specified type
--- @param ast parser.object
--- @param type string
--- @param callback fun(src: parser.object): any
--- @return any
function M.eachSourceType(ast, type, callback)
    local cache = getSourceTypeCache(ast)
    local myCache = cache[type]
    if not myCache then
        return
    end
    for i = 1, #myCache do
        local res = callback(myCache[i])
        if res ~= nil then
            return res
        end
    end
end

--- @param ast parser.object
--- @param tps string[]
--- @param callback fun(src: parser.object)
function M.eachSourceTypes(ast, tps, callback)
    local cache = getSourceTypeCache(ast)
    for x = 1, #tps do
        local tpCache = cache[tps[x]]
        if tpCache then
            for i = 1, #tpCache do
                callback(tpCache[i])
            end
        end
    end
end

--- Traverse all sources
--- @param ast parser.object
--- @param callback fun(src: parser.object): boolean?
function M.eachSource(ast, callback)
    local cache = ast._eachCache
    if not cache then
        cache = { ast }
        ast._eachCache = cache
        local mark = {}
        local index = 1
        while true do
            local obj = cache[index]
            if not obj then
                break
            end
            index = index + 1
            if not mark[obj] then
                mark[obj] = true
                addChilds(cache, obj)
            end
        end
    end
    for i = 1, #cache do
        local res = callback(cache[i])
        if res == false then
            return
        end
    end
end

--- @param source   parser.object
--- @param callback fun(src: parser.object)
function M.eachChild(source, callback)
    local f = eachChildMap[source.type]
    if not f then
        return
    end
    f(source, callback)
end

--- Get the specified special
--- @param ast parser.object
--- @param name string
--- @param callback fun(src: parser.object)
function M.eachSpecialOf(ast, name, callback)
    local root = M.getRoot(ast)
    local state = root.state
    if not state.specials then
        return
    end
    local specials = state.specials[name]
    if not specials then
        return
    end
    for i = 1, #specials do
        callback(specials[i])
    end
end

--- Split position into row number and column number
---
---The first line is 0
--- @param position integer
--- @return integer row
--- @return integer col
function M.rowColOf(position)
    return position // 10000, position % 10000
end

--- Combine rows and columns into position
---
--- The first line is 0
--- @param row integer
--- @param col integer
--- @return integer
function M.positionOf(row, col)
    return row * 10000 + math.min(col, 10000 - 1)
end

function M.positionToOffsetByLines(lines, position)
    local row, col = M.rowColOf(position)
    if row < 0 then
        return 0
    end
    if row > #lines then
        return lines.size
    end
    local offset = lines[row] + col - 1
    if lines[row + 1] and offset >= lines[row + 1] then
        return lines[row + 1] - 1
    elseif offset > lines.size then
        return lines.size
    end
    return offset
end

--- Return to full text cursor position
--- @param state any
--- @param position integer
function M.positionToOffset(state, position)
    return M.positionToOffsetByLines(state.lines, position)
end

--- @param lines integer[]
--- @param offset integer
function M.offsetToPositionByLines(lines, offset)
    local left = 0
    local right = #lines
    local row = 0
    while true do
        row = (left + right) // 2
        if row == left then
            if right ~= left then
                if lines[right] - 1 <= offset then
                    row = right
                end
            end
            break
        end
        local start = lines[row] - 1
        if start > offset then
            right = row
        else
            left = row
        end
    end
    local col = offset - lines[row] + 1
    return M.positionOf(row, col)
end

function M.offsetToPosition(state, offset)
    return M.offsetToPositionByLines(state.lines, offset)
end

function M.getLineRange(state, row)
    if not state.lines[row] then
        return 0
    end
    local nextLineStart = state.lines[row + 1] or #state.lua
    for i = nextLineStart - 1, state.lines[row], -1 do
        local w = state.lua:sub(i, i)
        if w ~= '\r' and w ~= '\n' then
            return i - state.lines[row] + 1
        end
    end
    return 0
end

local assignTypeMap = {
    ['setglobal'] = true,
    ['local'] = true,
    ['self'] = true,
    ['setlocal'] = true,
    ['setfield'] = true,
    ['setmethod'] = true,
    ['setindex'] = true,
    ['tablefield'] = true,
    ['tableindex'] = true,
    ['label'] = true,
    ['doc.class'] = true,
    ['doc.alias'] = true,
    ['doc.enum'] = true,
    ['doc.field'] = true,
    ['doc.class.name'] = true,
    ['doc.alias.name'] = true,
    ['doc.enum.name'] = true,
    ['doc.field.name'] = true,
    ['doc.type.field'] = true,
    ['doc.type.array'] = true,
}
function M.isAssign(source)
    local tp = source.type
    if assignTypeMap[tp] then
        return true
    end
    if tp == 'call' then
        local special = M.getSpecial(source.node)
        if special == 'rawset' then
            return true
        end
    end
    return false
end

local getTypeMap = {
    ['getglobal'] = true,
    ['getlocal'] = true,
    ['getfield'] = true,
    ['getmethod'] = true,
    ['getindex'] = true,
}
function M.isGet(source)
    local tp = source.type
    if getTypeMap[tp] then
        return true
    end
    if tp == 'call' then
        local special = M.getSpecial(source.node)
        if special == 'rawget' then
            return true
        end
    end
    return false
end

function M.getSpecial(source)
    if not source then
        return
    end
    return source.special
end

function M.getKeyNameOfLiteral(obj)
    if not obj then
        return
    end
    local tp = obj.type
    if tp == 'field' or tp == 'method' then
        return obj[1]
    elseif
        tp == 'string'
        or tp == 'number'
        or tp == 'integer'
        or tp == 'boolean'
        or tp == 'doc.type.integer'
        or tp == 'doc.type.string'
        or tp == 'doc.type.boolean'
    then
        return obj[1]
    end
end

--- @return string?
function M.getKeyName(obj)
    if not obj then
        return
    end
    local tp = obj.type
    if tp == 'getglobal' or tp == 'setglobal' then
        return obj[1]
    elseif tp == 'local' or tp == 'self' or tp == 'getlocal' or tp == 'setlocal' then
        return obj[1]
    elseif tp == 'getfield' or tp == 'setfield' or tp == 'tablefield' then
        if obj.field then
            return obj.field[1]
        end
    elseif tp == 'getmethod' or tp == 'setmethod' then
        if obj.method then
            return obj.method[1]
        end
    elseif tp == 'getindex' or tp == 'setindex' or tp == 'tableindex' then
        return M.getKeyNameOfLiteral(obj.index)
    elseif tp == 'tableexp' then
        return obj.tindex
    elseif tp == 'field' or tp == 'method' then
        return obj[1]
    elseif tp == 'doc.class' then
        return obj.class[1]
    elseif tp == 'doc.alias' then
        return obj.alias[1]
    elseif tp == 'doc.enum' then
        return obj.enum[1]
    elseif tp == 'doc.field' then
        return obj.field[1]
    elseif
        tp == 'doc.field.name'
        or tp == 'doc.type.name'
        or tp == 'doc.class.name'
        or tp == 'doc.alias.name'
        or tp == 'doc.enum.name'
        or tp == 'doc.extends.name'
    then
        return obj[1]
    elseif tp == 'doc.type.field' then
        return M.getKeyName(obj.name)
    end
    return M.getKeyNameOfLiteral(obj)
end

function M.getKeyTypeOfLiteral(obj)
    if not obj then
        return
    end
    local tp = obj.type
    if tp == 'field' or tp == 'method' then
        return 'string'
    elseif tp == 'string' then
        return 'string'
    elseif tp == 'number' then
        return 'number'
    elseif tp == 'integer' then
        return 'integer'
    elseif tp == 'boolean' then
        return 'boolean'
    end
end

function M.getKeyType(obj)
    if not obj then
        return
    end
    local tp = obj.type
    if tp == 'getglobal' or tp == 'setglobal' then
        return 'string'
    elseif tp == 'local' or tp == 'self' or tp == 'getlocal' or tp == 'setlocal' then
        return 'local'
    elseif tp == 'getfield' or tp == 'setfield' or tp == 'tablefield' then
        return 'string'
    elseif tp == 'getmethod' or tp == 'setmethod' then
        return 'string'
    elseif tp == 'getindex' or tp == 'setindex' or tp == 'tableindex' then
        return M.getKeyTypeOfLiteral(obj.index)
    elseif tp == 'tableexp' then
        return 'integer'
    elseif tp == 'field' or tp == 'method' then
        return 'string'
    elseif tp == 'doc.class' then
        return 'string'
    elseif tp == 'doc.alias' then
        return 'string'
    elseif tp == 'doc.enum' then
        return 'string'
    elseif tp == 'doc.field' then
        return type(obj.field[1])
    elseif tp == 'doc.type.field' then
        return type(obj.name[1])
    end
    if tp == 'doc.field.name' then
        return type(obj[1])
    end
    return M.getKeyTypeOfLiteral(obj)
end

--- Whether it is a global variable (including _G.XXX form)
--- @param source parser.object
--- @return boolean
function M.isGlobal(source)
    if source._isGlobal ~= nil then
        return source._isGlobal
    end
    if source.tag == '_ENV' then
        source._isGlobal = true
        return false
    end
    if source.special == '_G' then
        source._isGlobal = true
        return true
    end
    if source.type == 'setglobal' or source.type == 'getglobal' then
        if source.node and source.node.tag == '_ENV' then
            source._isGlobal = true
            return true
        end
    end
    if
        source.type == 'setfield'
        or source.type == 'getfield'
        or source.type == 'setindex'
        or source.type == 'getindex'
    then
        local current = source
        while current do
            local node = current.node
            if not node then
                break
            end
            if node.special == '_G' then
                source._isGlobal = true
                return true
            end
            if M.getKeyName(node) ~= '_G' then
                break
            end
            current = node
        end
    end
    if source.type == 'call' then
        local node = source.node
        if node.special == 'rawget' or node.special == 'rawset' then
            if source.args and source.args[1] then
                local isGlobal = source.args[1].special == '_G'
                source._isGlobal = isGlobal
                return isGlobal
            end
        end
    end
    source._isGlobal = false
    return false
end

function M.isInString(ast, position)
    return M.eachSourceContain(ast, position, function(source)
        if source.type == 'string' and source.start < position then
            return true
        end
    end)
end

function M.isInComment(ast, offset)
    for _, com in ipairs(ast.state.comms) do
        if offset >= com.start and offset <= com.finish then
            return true
        end
    end
    return false
end

function M.isOOP(source)
    if source.type == 'setmethod' or source.type == 'getmethod' then
        return true
    end
    if source.type == 'method' or source.type == 'field' or source.type == 'function' then
        return M.isOOP(source.parent)
    end
    return false
end

local basicTypeMap = {
    ['unknown'] = true,
    ['any'] = true,
    ['true'] = true,
    ['false'] = true,
    ['nil'] = true,
    ['boolean'] = true,
    ['integer'] = true,
    ['number'] = true,
    ['string'] = true,
    ['table'] = true,
    ['function'] = true,
    ['thread'] = true,
    ['userdata'] = true,
}

--- @param str string
--- @return boolean
function M.isBasicType(str)
    return basicTypeMap[str] == true
end

--- @param source parser.object
--- @return boolean
function M.isBlockType(source)
    return blockTypes[source.type] == true
end

--- @param source parser.object
--- @return parser.object?
function M.getSelfNode(source)
    if source.type == 'getlocal' or source.type == 'setlocal' then
        source = source.node
    end
    if source.type ~= 'self' then
        return
    end
    local args = source.parent
    if args.type == 'callargs' then
        local call = args.parent
        if call.type ~= 'call' then
            return
        end
        local getmethod = call.node
        if getmethod.type ~= 'getmethod' then
            return
        end
        return getmethod.node
    end
    if args.type == 'funcargs' then
        return M.getFunctionSelfNode(args.parent)
    end
end

--- @param func parser.object
--- @return parser.object?
function M.getFunctionSelfNode(func)
    if func.type ~= 'function' then
        return
    end
    local parent = func.parent
    if parent.type == 'setmethod' or parent.type == 'setfield' then
        return parent.node
    end
end

--- @param source parser.object
--- @return parser.object?
function M.getTopBlock(source)
    for _ = 1, 1000 do
        local block = source.parent
        if not block then
            return
        end
        if topBlockTypes[block.type] then
            return block
        end
        source = block
    end
end

--- @param source parser.object
--- @return boolean
function M.isParam(source)
    if source.type ~= 'local' and source.type ~= 'self' then
        return false
    end
    if source.parent.type ~= 'funcargs' then
        return false
    end
    return true
end

--- @param source parser.object
--- @return parser.object[]?
function M.getParams(source)
    if source.type == 'call' then
        local args = source.args
        if not args then
            return
        end
        assert(args.type == 'callargs', "call.args type is't callargs")
        return args
    elseif source.type == 'callargs' then
        return source
    elseif source.type == 'function' then
        local args = source.args
        if not args then
            return
        end
        assert(args.type == 'funcargs', "function.args type is't callargs")
        return args
    end
end

--- @param source parser.object
--- @param index integer
--- @return parser.object?
function M.getParam(source, index)
    local args = M.getParams(source)
    return args and args[index] or nil
end

return M
