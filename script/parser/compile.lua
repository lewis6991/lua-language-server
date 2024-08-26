local guide = require('parser.guide')

--- @param str string
--- @return table<integer, boolean>
local function stringToCharMap(str)
    local map = {}
    local pos = 1
    while pos <= #str do
        local byte = string.byte(str, pos, pos)
        map[string.char(byte)] = true
        pos = pos + 1
        if str:sub(pos, pos) == '-' and pos < #str then
            pos = pos + 1
            local byte2 = string.byte(str, pos, pos)
            assert(byte < byte2)
            for b = byte + 1, byte2 do
                map[string.char(b)] = true
            end
            pos = pos + 1
        end
    end
    return map
end

local CharMapWord = stringToCharMap('_a-zA-Z\x80-\xff')

local NLMap = {
    ['\n'] = true,
    ['\r'] = true,
    ['\r\n'] = true,
}

local GetToSetMap = {
    ['getglobal'] = 'setglobal',
    ['getlocal'] = 'setlocal',
    ['getfield'] = 'setfield',
    ['getindex'] = 'setindex',
    ['getmethod'] = 'setmethod',
}

local ChunkFinishMap = {
    ['end'] = true,
    ['else'] = true,
    ['elseif'] = true,
    ['in'] = true,
    ['then'] = true,
    ['until'] = true,
    [';'] = true,
    [']'] = true,
    [')'] = true,
    ['}'] = true,
}

--- Nodes

--- @alias parser.object
--- | parser.object.block
--- | parser.object.action
--- | parser.object.expr
--- | parser.object.forlist
--- | parser.object.main
--- | parser.object.name
--- | parser.object.funcargs
--- | parser.object.callargs
--- | parser.object.old

--- @class parser.object.base
--- @field start integer
--- @field finish integer
--- @field special? string
--- @field state? parser.state
--- @field next? parser.object
--- @field uri? string
--- @field hasExit? true
--- @field parent? parser.object

--- @class parser.object.setfield : parser.object.base
--- @field type 'setfield'

--- @class parser.object.setmethod : parser.object.base
--- @field type 'setmethod'
--- @field node unknown

--- @class parser.object.break : parser.object.base
--- @field type 'break'

--- @class parser.object.forlist : parser.object.base
--- @field type 'list'
--- @field [integer] parser.object.name

--- @class parser.object.goto : parser.object.base
--- @field type 'goto'
--- @field node? parser.object.label
--- @field keyStart integer

--- @class parser.object.localattrs : parser.object.base
--- @field type 'localattrs'
--- @field parent? parser.object
--- @field [integer] parser.object.localattr

--- @class parser.object.localattr : parser.object.base
--- @field type 'localattr'
--- @field parent parser.object.localattrs
--- @field [1]? string

--- @class parser.object.local : parser.object.base
--- @field type 'local'
--- @field effect integer
--- @field attrs parser.object.localattrs
--- @field ref? parser.object.expr[] References to local
--- @field locPos? integer Start position of the 'local' keyword
--- @field [1] string Name of local variable

--- @class parser.object.self : parser.object.local
--- @field parent parser.object.callargs|parser.object.funcargs
--- @field type 'self'

--- @class parser.object.return : parser.object.base
--- @field type 'return'

--- @class parser.object.dot : parser.object.base
--- @field type 'dot'

--- @class parser.object.colon : parser.object.base
--- @field type ':'

--- @class parser.object.name : parser.object.base
--- @field type 'name'
--- @field [1] string value

--- @class parser.object.field : parser.object.base
--- @field type 'field'
--- @field [1] string value

--- @class parser.object.method : parser.object.base
--- @field type 'method'

--- @class parser.object.getmethod : parser.object.base
--- @field type 'getmethod'
--- @field node parser.object.expr
--- @field colon parser.object.colon

--- @alias parser.object.simple
--- | parser.object.name
--- | parser.object.getglobal
--- | parser.object.getlocal

--- @alias parser.object.comment
--- | parser.object.comment.short
--- | parser.object.comment.long
--- | parser.object.comment.cshort

--- @class parser.object.comment.long : parser.object.base
--- @field type 'comment.long'
--- @field text string
--- @field mark integer

--- @class parser.object.comment.short : parser.object.base
--- @field type 'comment.short'
--- @field text string

--- @class parser.object.comment.cshort : parser.object.base
--- @field type 'comment.cshort'
--- @field text string

--- Expressions

--- @alias parser.object.expr
--- | parser.object.binop
--- | parser.object.boolean
--- | parser.object.explist
--- | parser.object.getglobal
--- | parser.object.getlocal
--- | parser.object.label
--- | parser.object.number
--- | parser.object.integer
--- | parser.object.paren
--- | parser.object.string
--- | parser.object.unary
--- | parser.object.varargs
--- | parser.object.simple
--- | parser.object.table
--- | parser.object.nil
--- | parser.object.index
--- | parser.object.tableindex
--- | parser.object.tableexp
--- | parser.object.tablefield
--- | parser.object.getindex
--- | parser.object.getmethod
--- | parser.object.getfield
--- | parser.object.call

--- @class parser.binop
--- @field type 'or' | 'and' | '<=' | '>=' | '<' | '>' | '~=' | '==' | '|' | '~' | '&' | '<<' | '>>' | '..' | '+' | '-' | '*' | '//' | '/' | '%' | '^'
--- @field start integer
--- @field finish integer

--- @class parser.object.binop : parser.object.base
--- @field type 'binary
--- @field op parser.binop
--- @field [1] parser.object.expr
--- @field [2] parser.object.expr?

--- @class parser.object.nil : parser.object.base
--- @field type 'nil'

--- @class parser.object.getfield : parser.object.base
--- @field type 'getfield'
--- @field dot parser.object.dot
--- @field field? parser.object.field

--- @class parser.object.callargs : parser.object.base
--- @field type 'callargs'
--- @field parent parser.object.call
--- @field [integer] parser.object.expr

--- @class parser.object.call : parser.object.base
--- @field type 'call'
--- @field args? parser.object.callargs
--- @field node parser.object.expr

--- @class parser.object.index : parser.object.base
--- @field type 'index'
--- @field index? parser.object.expr

--- @class parser.object.getindex : parser.object.base
--- @field type 'getindex'
--- @field index? parser.object.expr
--- @field node parser.object.expr

--- @class parser.object.tableexp : parser.object.base
--- @field type 'tableexp'
--- @field value parser.object.expr
--- @field tindex? integer

--- @class parser.object.tableindex : parser.object.base
--- @field type 'tableindex'
--- @field index? parser.object.expr
--- @field node parser.object.table
--- @field range? integer
--- @field value? parser.object.expr

--- @class parser.object.tablefield : parser.object.base
--- @field type 'tablefield'
--- @field field parser.object.field
--- @field value? parser.object.expr
--- @field node? parser.object.table

--- @alias parser.object.tableentry
--- | parser.object.tablefield
--- | parser.object.tableexp
--- | parser.object.tableindex
--- | parser.object.varargs

--- @class parser.object.table : parser.object.base
--- @field type 'table'
--- @field bstart integer
--- @field bfinish integer
--- @field [integer] parser.object.tableentry

--- @class parser.object.boolean : parser.object.base
--- @field type 'boolean'
--- @field [1] boolean value

--- @class parser.object.explist : parser.object.base
--- @field type 'list'
--- @field [integer] parser.object.expr

--- @class parser.object.getglobal : parser.object.base
--- @field type 'getglobal'
--- @field node parser.object.local
--- @field [1] string Name

--- @class parser.object.setlocal : parser.object.base
--- @field type 'setlocal'
--- @field node parser.object.local|parser.object.self

--- @class parser.object.setindex : parser.object.base
--- @field type 'setindex'

--- @class parser.object.getlocal : parser.object.base
--- @field type 'getlocal'
--- @field node parser.object.local|parser.object.self
--- @field [1] string Name

--- @class parser.object.label : parser.object.base
--- @field type 'label'
--- @field ref? parser.object.goto[] References to label
--- @field [1] string value

--- @class parser.object.number : parser.object.base
--- @field type 'number'
--- @field [1] number value

--- @class parser.object.integer : parser.object.base
--- @field type 'integer'
--- @field [1] integer value

--- @class parser.object.paren : parser.object.base
--- @field type 'paren'
--- @field exp? parser.object.expr

--- @class parser.object.string : parser.object.base
--- @field type 'string'
--- @field escs? (string|integer)[] [int, int, string, int, int, string, ...]
--- @field [1] string value
--- @field [2] string string delimiter

--- @class parser.object.unary : parser.object.base
--- @field type 'unary'
--- @field [1] parser.object.expr?

--- @class parser.object.varargs : parser.object.base
--- @field type 'varargs'
--- @field node? unknown

--- Blocks

--- @alias parser.object.action
--- | parser.object.label
--- | parser.object.local
--- | parser.object.do
--- | parser.object.if
--- | parser.object.for
--- | parser.object.in
--- | parser.object.loop
--- | parser.object.while
--- | parser.object.repeat
--- | parser.object.function
--- | parser.object.expr
--- | parser.object.break
--- | parser.object.return
--- | parser.object.goto
--- | parser.object.setlocal
--- | parser.object.setfield
--- | parser.object.setmethod
--- | parser.object.setindex

--- @alias parser.object.block
--- | parser.object.main
--- | parser.object.do
--- | parser.object.if
--- | parser.object.ifblock
--- | parser.object.elseifblock
--- | parser.object.elseblock
--- | parser.object.for
--- | parser.object.function
--- | parser.object.lambda
--- | parser.object.loop
--- | parser.object.in
--- | parser.object.repeat
--- | parser.object.while

--- @class parser.object.block.base : parser.object.base
--- @field bstart integer Block start
--- @field bfinish? integer Block end
--- @field labels? table<string,parser.object.label>
--- @field locals parser.object.local[]
--- @field gotos parser.object.goto[]
--- @field breaks parser.object.break[]
--- @field hasGoTo? true
--- @field hasReturn? true
--- @field hasBreak? true
--- @field [integer] parser.object

--- @class parser.object.main : parser.object.block.base
--- @field type 'main'
--- @field returns? parser.object.return[]

--- @class parser.object.do : parser.object.block.base
--- @field type 'do'
--- @field keyword [integer,integer]

--- @class parser.object.funcargs : parser.object.base
--- @field type 'funcargs'
--- @field parent parser.object.function
--- @field [integer] parser.object.local|parser.object.self|parser.object.vararg

--- @class parser.object.vararg : parser.object.base
--- @field type '...'
--- @field [1] '...'
--- @field ref parser.object.varargs[]

--- @class parser.object.function : parser.object.block.base
--- @field type 'function'
--- @field keyword [integer,integer]
--- @field vararg? parser.object.vararg
--- @field args? parser.object.funcargs
--- @field name? parser.object.simple
--- @field returns? parser.object.return[]

--- @class parser.object.lambda : parser.object.block.base
--- @field args? parser.object.funcargs
--- @field returns? parser.object.return[]

--- Blocks: If

--- @class parser.object.if : parser.object.block.base
--- @field type 'if'
--- @field keyword [integer,integer]

--- @class parser.object.ifblock : parser.object.block.base
--- @field type 'ifblock'
--- @field parent parser.object.if
--- @field filter? parser.object.expr? Condition of if block
--- @field keyword [integer,integer]

--- @class parser.object.elseifblock : parser.object.block.base
--- @field type 'elseifblock'
--- @field parent parser.object.if
--- @field filter? parser.object.expr? Condition of if block
--- @field keyword [integer,integer]

--- @class parser.object.elseblock : parser.object.block.base
--- @field type 'elseblock'
--- @field parent parser.object.if
--- @field keyword [integer,integer]

--- Blocks: Loops

--- @class parser.object.for : parser.object.block.base
--- @field type 'for'
--- @field keyword [integer,integer]

--- @class parser.object.loop : parser.object.block.base
--- @field type 'loop'
--- @field stateVars integer
--- @field keyword [integer,integer]
--- @field loc? parser.object.local
--- @field init? parser.object.expr
--- @field max? parser.object.expr
--- @field step? parser.object.expr

--- @class parser.object.in : parser.object.block.base
--- @field type 'in'
--- @field stateVars integer
--- @field keyword [integer,integer, integer, integer]
--- @field exps parser.object.explist
--- @field keys parser.object.forlist

--- @class parser.object.repeat : parser.object.block.base
--- @field type 'repeat'
--- @field filter? parser.object.expr
--- @field keyword [integer,integer, integer, integer]

--- @class parser.object.while : parser.object.block.base
--- @field type 'while'
--- @field keyword [integer,integer]
--- @field filter? parser.object.expr

--- State

--- @class parser.state.err
--- @field at? parser.object.base
--- @field type string
--- @field start? integer
--- @field finish? integer
--- @field info? parser.info
--- @field fix? parser.fix
--- @field version? string[]|string
--- @field level? string | 'Error' | 'Warning'

--- @class parser.comm

--- @class parser.fix
--- @field title string
--- @field symbol? string
--- @field [1] {start?:integer, finish?: integer, text: string}

--- @class parser.info
--- @field symbol? string
--- @field version? string

--- @class parser.state
--- @field lua? string
--- @field uri? string
--- @field lines integer[]
--- @field version 'Lua 5.1' | 'Lua 5.2' | 'Lua 5.3' | 'Lua 5.4' | 'LuaJIT'
--- @field options table
--- @field ENVMode '@fenv' | '_ENV'
--- @field errs parser.state.err[]
--- @field specials? table<string,parser.object.base[]>
--- @field ast? parser.object
--- @field comms parser.object.comment[]

local State --- @type parser.state
local Lua --- @type string
local Line --- @type integer
local LineOffset --- @type integer
local Mode
local LastTokenFinish

local LineMult = 10000

--- @param offset integer
--- @param leftOrRight 'left'|'right'
local function getPosition(offset, leftOrRight)
    if not offset or offset > #Lua then
        return LineMult * Line + #Lua - LineOffset + 1
    end
    if leftOrRight == 'left' then
        return LineMult * Line + offset - LineOffset
    else
        return LineMult * Line + offset - LineOffset + 1
    end
end

local Token = {}

do -- Token interface
    local tokens = nil --- @type (integer|string)[]
    local index = nil --- @type integer

    function Token.init(lua)
        tokens = require('parser.tokens')(lua)
        index = 1
    end

    function Token.index()
        return index
    end

    function Token.setIndex(x)
        index = x
    end

    --- @param ... string Tokens
    --- @return string?
    function Token.get(...)
        local t = tokens[index + 1] --[[@as string]]
        if select('#', ...) == 0 then
            return t
        end

        for i = 1, select('#', ...) do
            if t == select(i, ...) then
                return t
            end
        end
    end

    --- @return string?
    function Token.getPrev()
        return tokens[index - 1] --[[@as string]]
    end

    --- @return integer?
    function Token.peek()
        return tokens[index + 3] --[[@as integer]]
    end

    function Token.next()
        index = index + 2
    end

    --- @return integer
    function Token.getPos()
        return tokens[index] --[[@as integer]]
    end

    --- @return integer
    function Token.getPrevPos()
        return tokens[index - 2] --[[@as integer]]
    end

    function Token.left()
        return getPosition(Token.getPos(), 'left')
    end

    function Token.right()
        return getPosition(Token.getPos() + #Token.get() - 1, 'right')
    end
end

--- @param name string
--- @param obj parser.object.base
local function addSpecial(name, obj)
    State.specials = State.specials or {}
    State.specials[name] = State.specials[name] or {}
    State.specials[name][#State.specials[name] + 1] = obj
    obj.special = name
end

--- @return string?  word
--- @return integer? startPosition
--- @return integer? finishPosition
local function peekWord()
    local token = Token.get()
    if not token or not CharMapWord[token:sub(1, 1)] then
        return
    end
    return token, Token.left(), Token.right()
end

local function lastRightPosition()
    local token = Token.getPrev()
    if not token then
        return 0
    end
    if NLMap[token] then
        return LastTokenFinish
    elseif token then
        return getPosition(Token.getPrevPos() + #token - 1, 'right')
    else
        return getPosition(#Lua, 'right')
    end
end

local Error = {
    --- @type fun(err:parser.state.err):parser.state.err?
    push = nil
}

--- @param ty string
--- @param attr? {start?:integer, finish?:integer, fix?:parser.fix}
function Error.token(ty, attr)
    attr = attr or {}
    --- @cast attr parser.state.err
    attr.type = ty
    if not attr.start or not attr.finish then
        attr.start = attr.start or Token.left()
        attr.finish = attr.finish or Token.right()
    end

    for _, fix in ipairs(attr.fix or {}) do
        if fix[1] then
            fix[1].start = fix[1].start or attr.start
            fix[1].finish = fix[1].finish or attr.finish
        end
    end

    Error.push(attr)
end

--- @param symbol string
--- @param start? integer
--- @param finish? integer
function Error.missSymbol(symbol, start, finish)
    Error.push({
        type = 'MISS_SYMBOL',
        start = start or lastRightPosition(),
        finish = finish or start or lastRightPosition(),
        info = {
            symbol = symbol,
        },
    })
end

function Error.missExp()
    Error.push({
        type = 'MISS_EXP',
        start = lastRightPosition(),
        finish = lastRightPosition(),
    })
end

--- @param pos? integer
function Error.missName(pos)
    Error.push({
        type = 'MISS_NAME',
        start = pos or lastRightPosition(),
        finish = pos or lastRightPosition(),
    })
end

--- @param relatedStart integer
--- @param relatedFinish integer
function Error.missEnd(relatedStart, relatedFinish)
    Error.push({
        type = 'MISS_SYMBOL',
        start = lastRightPosition(),
        finish = lastRightPosition(),
        info = {
            symbol = 'end',
            related = {
                {
                    start = relatedStart,
                    finish = relatedFinish,
                },
            },
        },
    })
    Error.push({
        type = 'MISS_END',
        start = relatedStart,
        finish = relatedFinish,
    })
end

local function unknownSymbol(start, finish, token)
    token = token or Token.get()
    if not token then
        return false
    end
    Error.token('UNKNOWN_SYMBOL', {
        start = start,
        finish = finish,
        info = {
            symbol = token,
        },
    })
    return true
end

local function skipUnknownSymbol()
    if unknownSymbol() then
        Token.next()
        return true
    end
    return false
end

local function skipNL()
    local token = Token.get()
    if not NLMap[token] then
        return false
    end
    local prevToken = Token.getPrev()
    if prevToken and not NLMap[prevToken] then
        LastTokenFinish = lastRightPosition()
    end
    Line = Line + 1
    LineOffset = Token.getPos() + #token
    Token.next()
    State.lines[Line] = LineOffset
    return true
end

local function getSavePoint()
    local index = Token.index()
    local line = Line
    local lineOffset = LineOffset
    local errs = State.errs
    local errCount = #errs
    return function()
        Token.setIndex(index)
        Line = line
        LineOffset = lineOffset
        for i = errCount + 1, #errs do
            errs[i] = nil
        end
    end
end

local function fastForwardToken(offset)
    while true do
        local myOffset = Token.getPos()
        if not myOffset or myOffset >= offset then
            break
        end
        local token = Token.get()
        if NLMap[token] then
            Line = Line + 1
            LineOffset = Token.getPos() + #token
            State.lines[Line] = LineOffset
        end
        Token.next()
    end
end

local function resolveLongString(finishMark)
    skipNL()
    local miss

    local start = Token.getPos()

    local finishOffset = Lua:find(finishMark, start, true)
    if not finishOffset then
        finishOffset = #Lua + 1
        miss = true
    end

    local stringResult = start and Lua:sub(start, finishOffset - 1) or ''

    local lastLN = stringResult:find('[\r\n][^\r\n]*$')
    if lastLN then
        stringResult = stringResult:gsub('\r\n?', '\n')
    end

    if finishMark == ']]' and State.version == 'Lua 5.1' then
        local nestOffset = Lua:find('[[', start, true)
        if nestOffset and nestOffset < finishOffset then
            fastForwardToken(nestOffset)
            local nestStartPos = getPosition(nestOffset, 'left')
            local nestFinishPos = getPosition(nestOffset + 1, 'right')
            Error.push({
                type = 'NESTING_LONG_MARK',
                start = nestStartPos,
                finish = nestFinishPos,
            })
        end
    end

    fastForwardToken(finishOffset + #finishMark)
    if miss then
        local pos = getPosition(#Lua, 'right')
        Error.push({
            type = 'MISS_SYMBOL',
            start = pos,
            finish = pos,
            info = {
                symbol = finishMark,
            },
            fix = {
                title = 'ADD_LSTRING_END',
                {
                    start = pos,
                    finish = pos,
                    text = finishMark,
                },
            },
        })
    end

    return stringResult, getPosition(finishOffset + #finishMark - 1, 'right')
end

-- Parsing is naturally recursive, so store parsing functions in a table to
-- avoid forward declaration
local P = {}

--- @return parser.object.string?
function P.LongString()
    if not Token.get('[') then
        return
    end
    local start, finish, mark = Lua:find('^(%[%=*%[)', Token.getPos())
    if not start then
        return
    end
    fastForwardToken(finish + 1)
    local startPos = getPosition(start, 'left')
    local finishMark = mark:gsub('%[', ']')
    local stringResult, finishPos = resolveLongString(finishMark)
    --- @type parser.object.string
    return {
        type = 'string',
        start = startPos,
        finish = finishPos,
        [1] = stringResult,
        [2] = mark,
    }
end

--- @param left integer
local function pushCommentHeadError(left)
    if not State.options.nonstandardSymbol['//'] then
        Error.token('ERR_COMMENT_PREFIX', {
            start = left,
            finish = left + 2,
            fix = { title = 'FIX_COMMENT_PREFIX', { text = '--' } },
        })
    end
end

local function pushLongCommentError(left, right)
    if State.options.nonstandardSymbol['/**/'] then
        return
    end
    Error.push({
        type = 'ERR_C_LONG_COMMENT',
        start = left,
        finish = right,
        fix = {
            title = 'FIX_C_LONG_COMMENT',
            {
                start = left,
                finish = left + 2,
                text = '--[[',
            },
            {
                start = right - 2,
                finish = right,
                text = '--]]',
            },
        },
    })
end

local function skipComment(isAction)
    local token = Token.get()
    if token == '--' or (token == '//' and (isAction or State.options.nonstandardSymbol['//'])) then
        local start = Token.getPos()
        local left = Token.left()
        local chead = false

        if Token.get('//') then
            chead = true
            pushCommentHeadError(left)
        end

        Token.next()
        local str = start + 2 == Token.getPos() and P.LongString()

        if str then
            local longComment = str --[[@as parser.object.comment.long]]
            longComment.type = 'comment.long'
            longComment.text = longComment[1]
            longComment.mark = longComment[2]
            longComment[1] = nil
            longComment[2] = nil
            State.comms[#State.comms + 1] = longComment
            return true
        end

        while true do
            local nl = Token.get()
            if not nl or NLMap[nl] then
                break
            end
            Token.next()
        end

        local right = Token.getPos() and (Token.getPos() - 1) or #Lua

        State.comms[#State.comms + 1] = {
            type = chead and 'comment.cshort' or 'comment.short',
            start = left,
            finish = getPosition(right, 'right'),
            text = Lua:sub(start + 2, right),
        }

        return true
    elseif Token.get('/*') then
        local left = Token.left()
        Token.next()
        local result, right = resolveLongString('*/')
        pushLongCommentError(left, right)
        State.comms[#State.comms + 1] = {
            type = 'comment.long',
            start = left,
            finish = right,
            text = result,
        }
        return true
    end
    return false
end

--- @param isAction? boolean
local function skipSpace(isAction)
    repeat
    until not skipNL() and not skipComment(isAction)
end

local function skipSeps()
    while true do
        skipSpace()
        if Token.get(',') then
            Error.missExp()
            Token.next()
        else
            break
        end
    end
end

--- @param isAction? boolean
--- @return boolean
local function expectAssign(isAction)
    if Token.get('=') then
        Token.next()
        return true
    elseif Token.get('==') then
        Error.token('ERR_ASSIGN_AS_EQ', {
            fix = { title = 'FIX_ASSIGN_AS_EQ', { text = '=' } },
        })
        Token.next()
        return true
    end

    if isAction then
        local token = Token.get('+=', '-=', '*=', '/=', '%=', '^=', '//=', '|=', '&=', '>>=', '<<=')
        if token then
            if not State.options.nonstandardSymbol[token] then
                unknownSymbol()
            end
            Token.next()
            return true
        end
    end
    return false
end

--- @return unknown
local function initObj(ty)
    return {
        type = ty,
        start = Token.left(),
        finish = Token.right(),
    }
end

local UnaryAlias = {
    ['!'] = 'not',
}

local UnarySymbol = {
    ['not'] = 11,
    ['#'] = 11,
    ['~'] = 11,
    ['-'] = 11,
}

local function unaryOP()
    local token = Token.get()
    local symbol = UnarySymbol[token] and token or UnaryAlias[token]
    if not symbol then
        return
    end
    local myLevel = UnarySymbol[symbol]
    local op = initObj(symbol)
    Token.next()
    return op, myLevel
end

local Chunk --- @type parser.Chunk

--- @return parser.object.localattrs?
function P.LocalAttrs()
    --- @type parser.object.localattrs?
    local attrs
    while true do
        skipSpace()
        if not Token.get('<') then
            break
        end
        if not attrs then
            attrs = {
                type = 'localattrs',
            }
        end
        local attr = initObj('localattr') --- @type parser.object.localattr
        attr.parent = attrs
        attrs[#attrs + 1] = attr
        Token.next()
        skipSpace()

        local word, wstart, wfinish = peekWord()
        if word then
            assert(wstart and wfinish)
            attr[1] = word
            attr.finish = wfinish
            Token.next()
            if word ~= 'const' and word ~= 'close' then
                Error.push({
                    type = 'UNKNOWN_ATTRIBUTE',
                    start = wstart,
                    finish = wfinish,
                })
            end
        else
            Error.missName()
        end
        attr.finish = lastRightPosition()
        skipSpace()

        if Token.get('>') then
            attr.finish = Token.right()
            Token.next()
        elseif Token.get('>=') then
            attr.finish = Token.right()
            Error.token('MISS_SPACE_BETWEEN')
            Token.next()
        else
            Error.missSymbol('>')
        end

        if State.version ~= 'Lua 5.4' then
            Error.push({
                type = 'UNSUPPORT_SYMBOL',
                at = attr,
                version = 'Lua 5.4',
                info = {
                    version = State.version,
                },
            })
        end
    end

    return attrs
end

--- @param obj parser.object.base
--- @param attrs? parser.object.localattrs
--- @return parser.object.local
local function createLocal(obj, attrs)
    local obj1 = obj --[[@as parser.object.local]]
    obj1.type = 'local'
    obj1.effect = obj1.finish

    if attrs then
        obj1.attrs = attrs
        attrs.parent = obj1
    end

    Chunk.addLocal(obj1)

    return obj1
end

--- @return parser.object.nil?
function P.Nil()
    if Token.get() ~= 'nil' then
        return
    end
    local obj = initObj('nil') --- @type parser.object.nil
    Token.next()
    return obj
end

--- @return parser.object.boolean?
function P.Boolean()
    local token = Token.get()
    if token ~= 'true' and token ~= 'false' then
        return
    end
    local obj = initObj('boolean') --- @type parser.object.boolean
    obj[1] = token == 'true' and true or false
    Token.next()
    return obj
end

do -- P.ShortString
    local function parseStringUnicode()
        local offset = Token.getPos() + 1

        if Lua:sub(offset, offset) ~= '{' then
            local pos = getPosition(offset, 'left')
            Error.missSymbol('{', pos)
            return nil, offset
        end

        local leftPos = getPosition(offset, 'left')
        local x16 = Lua:match('^%w*', offset + 1)
        local rightPos = getPosition(offset + #x16, 'right')
        offset = offset + #x16 + 1

        if Lua:sub(offset, offset) == '}' then
            offset = offset + 1
            rightPos = rightPos + 1
        else
            Error.missSymbol('}', rightPos)
        end

        offset = offset + 1
        if #x16 == 0 then
            Error.push({
                type = 'UTF8_SMALL',
                start = leftPos,
                finish = rightPos,
            })
            return '', offset
        end

        if
            State.version ~= 'Lua 5.3'
            and State.version ~= 'Lua 5.4'
            and State.version ~= 'LuaJIT'
        then
            Error.push({
                type = 'ERR_ESC',
                start = leftPos - 2,
                finish = rightPos,
                version = { 'Lua 5.3', 'Lua 5.4', 'LuaJIT' },
                info = {
                    version = State.version,
                },
            })
            return nil, offset
        end

        local byte = tonumber(x16, 16)

        if not byte then
            for i = 1, #x16 do
                if not tonumber(x16:sub(i, i), 16) then
                    Error.push({
                        type = 'MUST_X16',
                        start = leftPos + i,
                        finish = leftPos + i + 1,
                    })
                end
            end
            return nil, offset
        end

        if State.version == 'Lua 5.4' then
            if byte < 0 or byte > 0x7FFFFFFF then
                Error.push({
                    type = 'UTF8_MAX',
                    start = leftPos,
                    finish = rightPos,
                    info = {
                        min = '00000000',
                        max = '7FFFFFFF',
                    },
                })
                return nil, offset
            end
        else
            if byte < 0 or byte > 0x10FFFF then
                Error.push({
                    type = 'UTF8_MAX',
                    start = leftPos,
                    finish = rightPos,
                    version = byte <= 0x7FFFFFFF and 'Lua 5.4' or nil,
                    info = {
                        min = '000000',
                        max = '10FFFF',
                    },
                })
            end
        end

        if byte >= 0 and byte <= 0x10FFFF then
            return utf8.char(byte), offset
        end

        return '', offset
    end

    local stringPool = {} --- @type table<integer,string>

    local EscMap = {
        ['a'] = '\a',
        ['b'] = '\b',
        ['f'] = '\f',
        ['n'] = '\n',
        ['r'] = '\r',
        ['t'] = '\t',
        ['v'] = '\v',
        ['\\'] = '\\',
        ["'"] = "'",
        ['"'] = '"',
    }

    --- @param mark string
    --- @param escs (string|integer)[]
    --- @param strIndex integer
    --- @param currOffset integer
    --- @return integer strIndex
    --- @return integer currOffset
    local function parseStringEsc(mark, escs, strIndex, currOffset)
        strIndex = strIndex + 1
        stringPool[strIndex] = Lua:sub(currOffset, Token.getPos() - 1)
        currOffset = Token.getPos()
        Token.next()

        if not Token.getPos() then
            return strIndex, currOffset
        end

        local escLeft = getPosition(currOffset, 'left')

        local function addEsc(ty, finish)
            escs[#escs + 1] = escLeft
            escs[#escs + 1] = finish
            escs[#escs + 1] = ty
        end

        -- has space?
        if Token.getPos() - currOffset > 1 then
            local right = getPosition(currOffset + 1, 'right')
            Error.push({ type = 'ERR_ESC', start = escLeft, finish = right })
            addEsc('err', right)
            Token.next()
            return strIndex, currOffset
        end

        local tokenNext = Token.get():sub(1, 1)
        if EscMap[tokenNext] or tokenNext == mark or NLMap[tokenNext] then
            strIndex = strIndex + 1
            currOffset = Token.getPos() + #tokenNext
            if skipNL() then
                stringPool[strIndex] = '\n'
            else
                stringPool[strIndex] = tokenNext == mark and mark or EscMap[tokenNext]
                Token.next()
            end
            addEsc('normal', escLeft + 2)
        elseif tokenNext == 'z' then
            -- The escape sequence '\z' skips the following span of whitespace characters,
            -- including line breaks; it is particularly useful to break and indent a long
            -- literal string into multiple lines without adding the newlines and spaces
            -- into the string contents.
            Token.next()
            if State.version == 'Lua 5.1' then
                Error.push({
                    type = 'ERR_ESC',
                    start = escLeft,
                    finish = escLeft + 2,
                    version = { 'Lua 5.2', 'Lua 5.3', 'Lua 5.4', 'LuaJIT' },
                    info = {
                        version = State.version,
                    },
                })
            else
                repeat
                until not skipNL()
                currOffset = Token.getPos()
            end
            addEsc('normal', escLeft + 2)
        elseif tokenNext:match('%d') then
            -- We can specify any byte in a short literal string, including embedded zeros,
            -- by its numeric value. This can be done ..., or with the escape sequence
            -- \ddd, where ddd is a sequence of up to three decimal digits. (Note that if a
            -- decimal escape sequence is to be followed by a digit, it must be expressed using
            -- exactly three digits.)

            -- TODO(lewis6991): Supported in Lua 5.1?
            local numbers = Token.get():match('^%d+')
            if #numbers > 3 then
                numbers = numbers:sub(1, 3)
            end
            currOffset = Token.getPos() + #numbers
            fastForwardToken(currOffset)
            local right = getPosition(currOffset - 1, 'right')
            local byte = math.tointeger(numbers)
            if byte and byte <= 255 then
                strIndex = strIndex + 1
                stringPool[strIndex] = string.char(byte)
            else
                Error.push({
                    type = 'ERR_ESC',
                    start = escLeft,
                    finish = right,
                })
            end
            addEsc('byte', right)
        elseif tokenNext == 'x' then
            local left = getPosition(Token.getPos() - 1, 'left')
            local x16 = Token.get():sub(2, 3)
            local byte = tonumber(x16, 16)
            if byte then
                currOffset = Token.getPos() + 3
                strIndex = strIndex + 1
                stringPool[strIndex] = string.char(byte)
            else
                currOffset = Token.getPos() + 1
                Error.push({
                    type = 'MISS_ESC_X',
                    start = getPosition(currOffset, 'left'),
                    finish = getPosition(currOffset + 1, 'right'),
                })
            end
            addEsc('byte', getPosition(currOffset + 1, 'right'))
            if State.version == 'Lua 5.1' then
                Error.push({
                    type = 'ERR_ESC',
                    start = left,
                    finish = left + 4,
                    version = { 'Lua 5.2', 'Lua 5.3', 'Lua 5.4', 'LuaJIT' },
                    info = {
                        version = State.version,
                    },
                })
            end
            Token.next()
        elseif tokenNext == 'u' then
            local str, newOffset = parseStringUnicode()
            if str then
                strIndex = strIndex + 1
                stringPool[strIndex] = str
            end
            currOffset = newOffset
            fastForwardToken(currOffset - 1)
            addEsc('unicode', getPosition(currOffset + 1, 'right'))
        else
            local right = getPosition(currOffset + 1, 'right')
            Error.push({ type = 'ERR_ESC', start = escLeft, finish = right })
            addEsc('err', right)
            Token.next()
        end
        return strIndex, currOffset
    end

    --- @return parser.object.string?
    function P.ShortString()
        local mark = Token.get("'", '"', '`')
        if not mark then
            return
        end
        assert(mark)
        local currOffset = Token.getPos() + 1
        local startPos = Token.left()
        Token.next()
        local strIndex = 0
        local escs = {}
        while true do
            local token = Token.get()
            if not token or NLMap[token] or token == mark then
                strIndex = strIndex + 1
                stringPool[strIndex] = Lua:sub(currOffset, (Token.getPos() or 0) - 1)
                if token == mark then
                    Token.next()
                else
                    Error.missSymbol(mark)
                end
                break
            elseif token == '\\' then
                strIndex, currOffset = parseStringEsc(mark, escs, strIndex, currOffset)
            else
                Token.next()
            end
        end

        local stringResult = table.concat(stringPool, '', 1, strIndex)
        --- @type parser.object.string
        local str = {
            type = 'string',
            start = startPos,
            finish = lastRightPosition(),
            escs = #escs > 0 and escs or nil,
            [1] = stringResult,
            [2] = mark,
        }

        if mark == '`' and not State.options.nonstandardSymbol[mark] then
            Error.push({
                type = 'ERR_NONSTANDARD_SYMBOL',
                start = str.start,
                finish = str.finish,
                info = {
                    symbol = '"',
                },
                fix = {
                    title = 'FIX_NONSTANDARD_SYMBOL',
                    symbol = '"',
                    {
                        start = str.start,
                        finish = str.start + 1,
                        text = '"',
                    },
                    {
                        start = str.finish - 1,
                        finish = str.finish,
                        text = '"',
                    },
                },
            })
        end

        return str
    end
end

--- @return parser.object.string?
function P.String()
    return P.ShortString() or P.LongString()
end

do -- P.Number
    local function parseNumber10(start)
        local integer = true
        local integerPart = Lua:match('^%d*', start)
        local offset = start + #integerPart
        -- float part
        if Lua:sub(offset, offset) == '.' then
            local floatPart = Lua:match('^%d*', offset + 1)
            integer = false
            offset = offset + #floatPart + 1
        end
        -- exp part
        local echar = Lua:sub(offset, offset)
        if echar:lower() == 'e' then
            integer = false
            offset = offset + 1
            local nextChar = Lua:sub(offset, offset)
            if nextChar == '-' or nextChar == '+' then
                offset = offset + 1
            end
            local exp = Lua:match('^%d*', offset)
            offset = offset + #exp
            if #exp == 0 then
                Error.push({
                    type = 'MISS_EXPONENT',
                    start = getPosition(offset - 1, 'right'),
                    finish = getPosition(offset - 1, 'right'),
                })
            end
        end
        return tonumber(Lua:sub(start, offset - 1)), offset, integer
    end

    local function parseNumber16(start)
        local integerPart = Lua:match('^[%da-fA-F]*', start)
        local offset = start + #integerPart
        local integer = true
        -- float part
        if Lua:sub(offset, offset) == '.' then
            local floatPart = Lua:match('^[%da-fA-F]*', offset + 1)
            integer = false
            offset = offset + #floatPart + 1
            if #integerPart == 0 and #floatPart == 0 then
                Error.push({
                    type = 'MUST_X16',
                    start = getPosition(offset - 1, 'right'),
                    finish = getPosition(offset - 1, 'right'),
                })
            end
        else
            if #integerPart == 0 then
                Error.push({
                    type = 'MUST_X16',
                    start = getPosition(offset - 1, 'right'),
                    finish = getPosition(offset - 1, 'right'),
                })
                return 0, offset
            end
        end
        -- exp part
        local echar = Lua:sub(offset, offset)
        if echar:lower() == 'p' then
            integer = false
            offset = offset + 1
            local nextChar = Lua:sub(offset, offset)
            if nextChar == '-' or nextChar == '+' then
                offset = offset + 1
            end
            local exp = Lua:match('^%d*', offset)
            offset = offset + #exp
        end
        local n = tonumber(Lua:sub(start - 2, offset - 1))
        return n, offset, integer
    end

    local function parseNumber2(start)
        local bins = Lua:match('^[01]*', start)
        local offset = start + #bins
        if State.version ~= 'LuaJIT' then
            Error.push({
                type = 'UNSUPPORT_SYMBOL',
                start = getPosition(start - 2, 'left'),
                finish = getPosition(offset - 1, 'right'),
                version = 'LuaJIT',
                info = {
                    version = 'Lua 5.4',
                },
            })
        end
        return tonumber(bins, 2), offset
    end

    local function dropNumberTail(offset, integer)
        local _, finish, word = Lua:find('^([%.%w_\x80-\xff]+)', offset)
        if not finish then
            return offset
        end
        if integer then
            if word:sub(1, 2):upper() == 'LL' then
                if State.version ~= 'LuaJIT' then
                    Error.push({
                        type = 'UNSUPPORT_SYMBOL',
                        start = getPosition(offset, 'left'),
                        finish = getPosition(offset + 1, 'right'),
                        version = 'LuaJIT',
                        info = {
                            version = State.version,
                        },
                    })
                end
                offset = offset + 2
                word = word:sub(offset)
            elseif word:sub(1, 3):upper() == 'ULL' then
                if State.version ~= 'LuaJIT' then
                    Error.push({
                        type = 'UNSUPPORT_SYMBOL',
                        start = getPosition(offset, 'left'),
                        finish = getPosition(offset + 2, 'right'),
                        version = 'LuaJIT',
                        info = {
                            version = State.version,
                        },
                    })
                end
                offset = offset + 3
                word = word:sub(offset)
            end
        end
        if word:sub(1, 1):upper() == 'I' then
            if State.version ~= 'LuaJIT' then
                Error.push({
                    type = 'UNSUPPORT_SYMBOL',
                    start = getPosition(offset, 'left'),
                    finish = getPosition(offset, 'right'),
                    version = 'LuaJIT',
                    info = {
                        version = State.version,
                    },
                })
            end
            offset = offset + 1
            word = word:sub(offset)
        end
        if #word > 0 then
            Error.push({
                type = 'MALFORMED_NUMBER',
                start = getPosition(offset, 'left'),
                finish = getPosition(finish, 'right'),
            })
        end
        return finish + 1
    end

    --- @return parser.object.number|parser.object.integer?
    function P.Number()
        local offset = Token.getPos()
        if not offset then
            return
        end
        local startPos = getPosition(offset, 'left')
        local neg
        if Lua:sub(offset, offset) == '-' then
            neg = true
            offset = offset + 1
        end
        local number, integer
        local firstChar = Lua:sub(offset, offset)
        if firstChar == '.' then
            number, offset = parseNumber10(offset)
            integer = false
        elseif firstChar == '0' then
            local nextChar = Lua:sub(offset + 1, offset + 1)
            if nextChar:lower() == 'x' then
                number, offset, integer = parseNumber16(offset + 2)
            elseif nextChar:lower() == 'b' then
                number, offset = parseNumber2(offset + 2)
                integer = true
            else
                number, offset, integer = parseNumber10(offset)
            end
        elseif firstChar:match('%d') then
            number, offset, integer = parseNumber10(offset)
        else
            return
        end

        number = number or 0

        if neg then
            number = -number
        end
        --- @type parser.object.number|parser.object.integer
        local result = {
            type = integer and 'integer' or 'number',
            start = startPos,
            finish = getPosition(offset - 1, 'right'),
            [1] = number,
        }
        offset = dropNumberTail(offset, integer)
        fastForwardToken(offset)
        return result
    end
end

-- goto is processed separately
local KeyWordMap = {
    ['and'] = true,
    ['break'] = true,
    ['do'] = true,
    ['else'] = true,
    ['elseif'] = true,
    ['end'] = true,
    ['false'] = true,
    ['for'] = true,
    ['function'] = true,
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

local function isKeyWord(word, tokenNext)
    if KeyWordMap[word] then
        return true
    elseif word == 'goto' then
        if State.version == 'Lua 5.1' then
            return false
        elseif State.version == 'LuaJIT' then
            return tokenNext and CharMapWord[tokenNext:sub(1, 1)] ~= nil
        end
        return true
    end
    return false
end

local ChunkStartMap = {
    ['do'] = true,
    ['else'] = true,
    ['elseif'] = true,
    ['for'] = true,
    ['function'] = true,
    ['if'] = true,
    ['local'] = true,
    ['repeat'] = true,
    ['return'] = true,
    ['then'] = true,
    ['until'] = true,
    ['while'] = true,
}

--- @return parser.object.name?
function P.Name(asAction)
    local word = peekWord()
    if not word then
        return
    elseif ChunkFinishMap[word] then
        return
    elseif asAction and ChunkStartMap[word] then
        return
    end

    if not State.options.unicodeName and word:find('[\x80-\xff]') then
        Error.token('UNICODE_NAME')
    end

    if isKeyWord(word, Token.get()) then
        Error.token('KEYWORD')
    end

    local obj = initObj('name') --- @type parser.object.name
    obj[1] = word
    Token.next()
    return obj
end

--- @param parent parser.object.for
--- @return parser.object.forlist|parser.object.name?
function P.NameOrList(parent)
    local first = P.Name()
    if not first then
        return
    end
    skipSpace()
    local list
    while true do
        if Token.get() ~= ',' then
            break
        end
        Token.next()
        skipSpace()
        local name = P.Name(true)
        if not name then
            Error.missName()
            break
        end
        if not list then
            list = {
                type = 'list',
                start = first.start,
                finish = first.finish,
                parent = parent,
                [1] = first,
            }
        end
        list[#list + 1] = name
        list.finish = name.finish
    end
    return list or first
end

local ListFinishMap = {
    ['end'] = true,
    ['else'] = true,
    ['elseif'] = true,
    ['in'] = true,
    ['then'] = true,
    ['do'] = true,
    ['until'] = true,
    ['for'] = true,
    ['if'] = true,
    ['local'] = true,
    ['repeat'] = true,
    ['return'] = true,
    ['while'] = true,
}

--- @param mini? boolean
--- @return parser.object.explist?
function P.ExpList(mini)
    --- @type parser.object.explist?
    local list
    local wantSep = false
    while true do
        skipSpace()
        local token = Token.get()
        if not token or ListFinishMap[token] then
            break
        elseif token == ',' then
            if not wantSep then
                Error.token('UNEXPECT_SYMBOL', { info = { symbol = ',' } })
            end
            wantSep = false
            Token.next()
        else
            if mini then
                if wantSep then
                    break
                end
                local tokenNext = peekWord()
                if
                    isKeyWord(tokenNext, Token.peek())
                    and tokenNext ~= 'function'
                    and tokenNext ~= 'true'
                    and tokenNext ~= 'false'
                    and tokenNext ~= 'nil'
                    and tokenNext ~= 'not'
                then
                    break
                end
            end
            local exp = P.Exp()
            if not exp then
                break
            end
            if wantSep then
                assert(list)
                Error.missSymbol(',', list[#list].finish, exp.start)
            end
            wantSep = true
            if not list then
                list = {
                    type = 'list',
                    start = exp.start,
                }
            end
            list[#list + 1] = exp
            list.finish = exp.finish
            exp.parent = list
        end
    end
    if not list then
        return
    end
    if not wantSep then
        Error.missExp()
    end
    return list
end

--- @return parser.object.index
local function parseIndex()
    local start = Token.left()
    Token.next()
    skipSpace()
    local exp = P.Exp()
    --- @type parser.object.index
    local index = {
        type = 'index',
        start = start,
        finish = exp and exp.finish or (start + 1),
        index = exp,
    }

    if exp then
        exp.parent = index
    else
        Error.missExp()
    end

    skipSpace()

    if Token.get(']') then
        index.finish = Token.right()
        Token.next()
    else
        Error.missSymbol(']')
    end

    return index
end

do -- P.Table
    --- @param wantSep boolean
    --- @return parser.object.tablefield?, boolean
    local function parseTableField(wantSep)
        local lastRight = lastRightPosition()

        if not peekWord() then
            return nil, wantSep
        end

        local savePoint = getSavePoint()
        local name = P.Name()
        if name then
            skipSpace()
            if Token.get('=') then
                Token.next()
                if wantSep then
                    Error.push({
                        type = 'MISS_SEP_IN_TABLE',
                        start = lastRight,
                        finish = getPosition(Token.getPos(), 'left'),
                    })
                end
                wantSep = true
                skipSpace()
                local fvalue = P.Exp()
                local field = name --[[@as parser.object.field]]
                field.type = 'field'
                --- @type parser.object.tablefield
                local tfield = {
                    type = 'tablefield',
                    start = name.start,
                    finish = name.finish,
                    range = fvalue and fvalue.finish,
                    field = field,
                    value = fvalue,
                }
                field.parent = tfield
                if fvalue then
                    fvalue.parent = tfield
                else
                    Error.missExp()
                end
                return tfield, wantSep
            end
        end

        savePoint()
        return nil, wantSep
    end

    --- @param exp parser.object.expr
    --- @param tindex integer
    --- @return parser.object.tableentry
    --- @return integer
    local function parseTableExp(exp, tindex)
        if exp.type == 'varargs' then
            --- @cast exp parser.object.varargs
            return exp, tindex
        end

        tindex = tindex + 1
        --- @type parser.object.tableexp
        local texp = {
            type = 'tableexp',
            start = exp.start,
            finish = exp.finish,
            tindex = tindex,
            value = exp,
        }
        exp.parent = texp
        return texp, tindex
    end

    --- @return parser.object.table?
    function P.Table()
        if not Token.get('{') then
            return
        end

        local tbl = initObj('table') --- @type parser.object.table
        tbl.bstart = tbl.finish
        Token.next()
        local index = 0
        local tindex = 0
        local wantSep = false
        while true do
            skipSpace(true)
            local token = Token.get()
            if token == '}' then
                tbl.bfinish = Token.left()
                Token.next()
                break
            elseif token == ',' or token == ';' then
                if not wantSep then
                    Error.missExp()
                end
                wantSep = false
                Token.next()
            else
                local tfield
                tfield, wantSep = parseTableField(wantSep)
                if tfield then
                    tfield.node = tbl
                    tfield.parent = tbl
                    index = index + 1
                    tbl[index] = tfield
                else
                    local lastRight = lastRightPosition()
                    local exp = P.Exp(true)
                    if exp then
                        if wantSep then
                            Error.push({
                                type = 'MISS_SEP_IN_TABLE',
                                start = lastRight,
                                finish = exp.start,
                            })
                        end
                        wantSep = true

                        local entry
                        entry, tindex = parseTableExp(exp, tindex)
                        entry.parent = tbl
                        index = index + 1
                        tbl[index] = entry
                    elseif token == '[' then
                        if wantSep then
                            Error.push({
                                type = 'MISS_SEP_IN_TABLE',
                                start = lastRight,
                                finish = Token.left(),
                            })
                        end
                        wantSep = true

                        local tblIndex = parseIndex() --[[@as parser.object.tableindex]]
                        tblIndex.type = 'tableindex'
                        tblIndex.node = tbl
                        tblIndex.parent = tbl
                        skipSpace()
                        index = index + 1
                        tbl[index] = tblIndex

                        if expectAssign() then
                            skipSpace()
                            local ivalue = P.Exp()
                            if ivalue then
                                ivalue.parent = tblIndex
                                tblIndex.range = ivalue.finish
                                tblIndex.value = ivalue
                            else
                                Error.missExp()
                            end
                        else
                            Error.missSymbol('=')
                        end
                    else
                        Error.missSymbol('}')
                        skipSpace()
                        tbl.bfinish = Token.left()
                        break
                    end
                end
            end
        end
        tbl.finish = lastRightPosition()
        return tbl
    end
end

local function addDummySelf(node, call)
    if not node or node.type ~= 'getmethod' then
        return
    end
    -- dummy param `self`
    if not call.args then
        call.args = {
            type = 'callargs',
            start = call.start,
            finish = call.finish,
            parent = call,
        }
    end
    --- @type parser.object.self
    local self = {
        type = 'self',
        start = node.colon.start,
        finish = node.colon.finish,
        parent = call.args,
        [1] = 'self',
    }
    table.insert(call.args, 1, self)
end

local Specials = {
    ['_G'] = true,
    ['rawset'] = true,
    ['rawget'] = true,
    ['setmetatable'] = true,
    ['require'] = true,
    ['dofile'] = true,
    ['loadfile'] = true,
    ['pcall'] = true,
    ['xpcall'] = true,
    ['pairs'] = true,
    ['ipairs'] = true,
    ['assert'] = true,
    ['error'] = true,
    ['type'] = true,
    ['os.exit'] = true,
}

local function bindSpecial(source, name)
    if Specials[name] then
        addSpecial(name, source)
    else
        local ospeicals = State.options.special
        if ospeicals and ospeicals[name] then
            addSpecial(ospeicals[name], source)
        end
    end
end

--- @param node parser.object.expr
--- @param currentName string?
--- @return parser.object.getfield, string?
local function parseGetField(node, currentName)
    local dot = initObj('.') --- @type parser.object.dot
    Token.next()
    skipSpace()
    local field = P.Name(true) --[[@as parser.object.field?]]

    --- @type parser.object.getfield
    local getfield = {
        type = 'getfield',
        start = node.start,
        finish = lastRightPosition(),
        node = node,
        dot = dot,
        field = field,
    }

    if field then
        field.parent = getfield
        field.type = 'field'
        if currentName then
            if node.type == 'getlocal' or node.type == 'getglobal' or node.type == 'getfield' then
                currentName = currentName .. '.' .. field[1]
                bindSpecial(getfield, currentName)
            else
                currentName = nil
            end
        end
    else
        Error.push({
            type = 'MISS_FIELD',
            start = lastRightPosition(),
            finish = lastRightPosition(),
        })
    end
    node.parent = getfield
    node.next = getfield
    return getfield, currentName
end

--- @param node parser.object.expr
--- @param lastMethod parser.object.getmethod?
--- @return parser.object.getmethod, parser.object.getmethod?
local function parseGetMethod(node, lastMethod)
    --- @type parser.object.colon
    local colon = {
        type = ':',
        start = getPosition(Token.getPos(), 'left'),
        finish = getPosition(Token.getPos(), 'right'),
    }
    Token.next()
    skipSpace()
    local method = P.Name(true) --[[@as parser.object.method?]]
    --- @type parser.object.getmethod
    local getmethod = {
        type = 'getmethod',
        start = node.start,
        finish = lastRightPosition(),
        node = node,
        colon = colon,
        method = method,
    }
    if method then
        method.parent = getmethod
        method.type = 'method'
    else
        Error.push({
            type = 'MISS_METHOD',
            start = lastRightPosition(),
            finish = lastRightPosition(),
        })
    end
    node.parent = getmethod
    node.next = getmethod
    if lastMethod then
        Error.missSymbol('(', getmethod.node.finish, getmethod.node.finish)
    end
    return getmethod, getmethod
end

do -- P.Simple
    local function checkAmbiguityCall(call, parenPos)
        if State.version ~= 'Lua 5.1' then
            return
        end
        local node = call.node
        if not node then
            return
        end
        local nodeRow = guide.rowColOf(node.finish)
        local callRow = guide.rowColOf(parenPos)
        if nodeRow == callRow then
            return
        end
        Error.push({
            type = 'AMBIGUOUS_SYNTAX',
            start = parenPos,
            finish = call.finish,
        })
    end

    --- @param node parser.object.expr
    --- @return parser.object.call
    local function parseCall(node)
        local start = Token.left()
        Token.next()

        local expList = P.ExpList()

        local finish
        if Token.get(')') then
            finish = Token.right()
            Token.next()
        else
            finish = lastRightPosition()
            Error.missSymbol(')')
        end

        --- @type parser.object.call
        local call = {
            type = 'call',
            start = node.start,
            finish = finish,
            node = node,
        }

        if expList then
            local args = expList --[[@as parser.object.callargs]]
            args.type = 'callargs'
            args.start = start
            args.finish = call.finish
            args.parent = call
            call.args = args
        end

        addDummySelf(node, call)
        checkAmbiguityCall(call, start)
        node.parent = call
        return call
    end

    --- @param node parser.object.expr
    --- @return parser.object.call?
    local function parseTableCall(node)
        local tbl = P.Table()
        if not tbl then
            return
        end

        --- @type parser.object.call
        local call = {
            type = 'call',
            start = node.start,
            finish = tbl.finish,
            node = node,
            args = {
                type = 'callargs',
                start = tbl.start,
                finish = tbl.finish,
                [1] = tbl,
            },
        }
        call.args.parent = call

        addDummySelf(node, call)
        tbl.parent = call.args
        node.parent = call
        return call
    end

    --- @return parser.object.call?
    local function parseShortStrCall(node)
        local str = P.ShortString()
        if not str then
            return
        end
        local call = {
            type = 'call',
            start = node.start,
            finish = str.finish,
            node = node,
        }
        local args = {
            type = 'callargs',
            start = str.start,
            finish = str.finish,
            parent = call,
            [1] = str,
        }
        call.args = args
        addDummySelf(node, call)
        str.parent = args
        node.parent = call
        return call
    end

    local function parseLongStrCall(node, str)
        local call = {
            type = 'call',
            start = node.start,
            finish = str.finish,
            node = node,
        }
        local args = {
            type = 'callargs',
            start = str.start,
            finish = str.finish,
            parent = call,
            [1] = str,
        }
        call.args = args
        addDummySelf(node, call)
        str.parent = args
        node.parent = call
        return call
    end

    --- @param node parser.object.expr
    --- @return parser.object.getindex
    local function parseGetIndex(node)
        local index = parseIndex() --[[@as parser.object.getindex]]
        index.type = 'getindex'
        index.start = node.start
        index.node = node
        node.next = index
        node.parent = index
        return index
    end

    --- @param node parser.object.expr
    --- @param funcName? boolean Parse function name
    --- @return parser.object.simple
    function P.Simple(node, funcName)
        local currentName --- @type string?
        if node.type == 'getglobal' or node.type == 'getlocal' then
            --- @cast node parser.object.getglobal|parser.object.getlocal
            currentName = node[1]
        end

        local lastMethod --- @type parser.object.getmethod?

        while true do
            if lastMethod and node.node == lastMethod then
                if node.type ~= 'call' then
                    Error.missSymbol('(', node.node.finish, node.node.finish)
                end
                lastMethod = nil
            end
            skipSpace()
            local token = Token.get()
            if token == '.' then
                node, currentName = parseGetField(node, currentName)
            elseif token == ':' then
                node, lastMethod = parseGetMethod(node, lastMethod)
            elseif token == '[' then
                local str = P.LongString()
                if str then
                    if funcName then
                        break
                    end
                    node = parseLongStrCall(node, str)
                else
                    node = parseGetIndex(node)
                    if funcName then
                        Error.push({
                            type = 'INDEX_IN_FUNC_NAME',
                            start = node.start,
                            finish = node.finish,
                        })
                    end
                end
            else
                if funcName then
                    break
                end
                if token == '(' then
                    node = parseCall(node)
                elseif token == '{' then
                    node = parseTableCall(node)
                elseif token == "'" or token == '"' or token == '`' then
                    node = parseShortStrCall(node)
                else
                    break
                end
            end
        end
        assert(node)

        if node.type == 'call' then
            local cnode = node.node
            if cnode == lastMethod then
                lastMethod = nil
            end

            if cnode and (cnode.special == 'error' or cnode.special == 'os.exit') then
                node.hasExit = true
            end
        end

        if node == lastMethod and funcName then
            lastMethod = nil
        end

        if lastMethod then
            Error.missSymbol('(', lastMethod.finish)
        end

        return node
    end
end

do -- P.Varargs
    --- local function a(...)
    ---   return function ()
    ---     return ... -- <--- ERROR: cannot use ... outside a vararg functions
    ---   end
    --- end
    --- @param varargs parser.object.varargs
    local function checkVarargs(varargs)
        for chunk in Chunk.iter_rev() do
            if chunk.vararg then
                chunk.vararg.ref = chunk.vararg.ref or {}
                chunk.vararg.ref[#chunk.vararg.ref + 1] = varargs
                varargs.node = chunk.vararg
                break
            end

            if chunk.type == 'main' then
                break
            elseif chunk.type == 'function' then
                Error.token('UNEXPECT_DOTS')
                break
            end
        end
    end

    --- @return parser.object.varargs?
    function P.Varargs()
        if Token.get() ~= '...' then
            return
        end
        local varargs = initObj('varargs') --- @type parser.object.varargs
        checkVarargs(varargs)
        Token.next()
        return varargs
    end
end

--- @return parser.object.expr?
function P.ParenExpr()
    if not Token.get('(') then
        return
    end

    local paren = initObj('paren') --- @type parser.object.paren
    Token.next()
    skipSpace()

    local exp = P.Exp()
    if exp then
        paren.exp = exp
        paren.finish = exp.finish
        exp.parent = paren
    else
        Error.missExp()
    end

    skipSpace()

    if Token.get(')') then
        paren.finish = Token.right()
        Token.next()
    else
        Error.missSymbol(')')
    end

    return P.Simple(paren, false)
end

--- @param name string
--- @param pos integer
--- @return parser.object.local?
local function getLocal(name, pos)
    for chunk in Chunk.iter_rev() do
        local res
        for _, loc in ipairs(chunk.locals or {}) do
            if loc.effect > pos then
                break
            end
            if loc[1] == name then
                if not res or res.effect < loc.effect then
                    res = loc
                end
            end
        end
        if res then
            return res
        end
    end
end

--- @param node parser.object.name
--- @return any
local function resolveName(node)
    if not node then
        return
    end

    local loc = getLocal(node[1], node.start)
    if loc then
        local getlocal = node --[[@as parser.object.getlocal]]
        getlocal.type = 'getlocal'
        getlocal.node = loc
        loc.ref = loc.ref or {}
        loc.ref[#loc.ref + 1] = getlocal
        if loc.special then
            addSpecial(loc.special, getlocal)
        end
    else
        local getglobal = node --[[@as parser.object.getglobal]]
        getglobal.type = 'getglobal'
        local global = getLocal(State.ENVMode, getglobal.start)
        if global then
            getglobal.node = global
            global.ref = global.ref or {}
            global.ref[#global.ref + 1] = getglobal
        end
    end

    local name = node[1]
    bindSpecial(node, name)
    return node
end

do -- P.Actions
    --- @param token any
    --- @return boolean
    local function isChunkFinishToken(token)
        local currentChunk = Chunk.get()
        if not currentChunk then
            return false
        end
        local tp = currentChunk.type
        if tp == 'main' then
            return false
        elseif tp == 'for' or tp == 'in' or tp == 'loop' or tp == 'function' then
            return token == 'end'
        elseif tp == 'if' or tp == 'ifblock' or tp == 'elseifblock' or tp == 'elseblock' then
            return token == 'then' or token == 'end' or token == 'else' or token == 'elseif'
        elseif tp == 'repeat' then
            return token == 'until'
        end
        return true
    end

    function P.Actions()
        local rtn --- @type parser.object.return?
        local last --- @type parser.object.action?

        while true do
            skipSpace(true)
            local token = Token.get()
            if token == ';' then
                Token.next()
            elseif ChunkFinishMap[token] and isChunkFinishToken(token) then
                break
            else
                local action = P.Action()
                if not action then
                    if not skipUnknownSymbol() then
                        break
                    end
                else
                    if not rtn and action.type == 'return' then
                        --- @cast action parser.object.return
                        rtn = action
                    end
                    last = action
                end
            end
        end

        if rtn and rtn ~= last then
            Error.token('ACTION_AFTER_RETURN', { at = rtn })
        end
    end
end

--- @return unknown
local function initBlock(ty)
    local start, finish = Token.left(), Token.right()
    return {
        type = ty,
        start = start,
        finish = finish,
        bstart = finish,
        keyword = { start, finish },
    }
end

--- @param obj parser.object.block
local function parseEnd(obj)
    if Token.get('end') then
        local left, right = Token.left(), Token.right()
        obj.finish = right
        obj.keyword[#obj.keyword + 1] = left
        obj.keyword[#obj.keyword + 1] = right
        Token.next()
    else
        obj.finish = lastRightPosition()
        Error.missEnd(obj.keyword[1], obj.keyword[2])
    end
end

do -- P.Function | P.Lambda
    --- @param params parser.object.funcargs?
    --- @param isLambda? boolean
    --- @return parser.object.funcargs
    local function parseParams(params, isLambda)
        params = params or {}
        params.type = 'funcargs'

        local lastSep
        local hasDots
        local endToken = isLambda and '|' or ')'

        while true do
            skipSpace()
            local token = Token.get()
            if not token or token == endToken then
                if lastSep then
                    Error.missName()
                end
                break
            elseif token == ',' then
                if lastSep or lastSep == nil then
                    Error.missName()
                else
                    lastSep = true
                end
                Token.next()
            elseif token == '...' then
                if lastSep == false then
                    Error.missSymbol(',')
                end
                lastSep = false
                local vararg = initObj('...') --- @as parser.object.vararg
                vararg.parent = params
                vararg[1] = '...'
                local chunk = Chunk.get()
                --- @cast chunk parser.object.function|parser.object.lambda
                chunk.vararg = vararg
                params[#params + 1] = vararg
                if hasDots then
                    Error.token('ARGS_AFTER_DOTS')
                end
                hasDots = true
                Token.next()
            elseif CharMapWord[token:sub(1, 1)] then
                if lastSep == false then
                    Error.missSymbol(',')
                end
                lastSep = false
                local start, finish = Token.left(), Token.right()
                params[#params + 1] = createLocal({
                    start = start,
                    finish = finish,
                    parent = params,
                    [1] = token,
                })
                if hasDots then
                    Error.push({ type = 'ARGS_AFTER_DOTS', start = start, finish = finish })
                end
                if isKeyWord(token, Token.getPrev()) then
                    Error.token('KEYWORD')
                end
                Token.next()
            else
                skipUnknownSymbol()
            end
        end

        return params
    end

    --- @param isLocal? boolean
    --- @param isAction? boolean
    --- @return parser.object.function?
    function P.Function(isLocal, isAction)
        if not Token.get('function') then
            return
        end
        local func = initBlock('function') --- @type parser.object.function
        Token.next()
        skipSpace(true)

        local hasLeftParen = Token.get('(')
        if not hasLeftParen then
            local name = P.Name()
            if name then
                local simple = P.Simple(name, true)
                if isLocal then
                    if simple == name then
                        createLocal(name)
                    else
                        resolveName(name)
                        Error.token('UNEXPECT_LFUNC_NAME', { at = simple.start })
                    end
                else
                    resolveName(name)
                end
                func.name = simple
                func.finish = simple.finish
                func.bstart = simple.finish
                if not isAction then
                    simple.parent = func
                    Error.token('UNEXPECT_EFUNC_NAME', { at = simple })
                end
                skipSpace(true)
                hasLeftParen = Token.get('(')
            end
        end

        local lastLocalCount = Chunk.localCount
        Chunk.localCount = 0
        Chunk.push(func)

        local params --- @type parser.object.funcargs?
        if func.name and func.name.type == 'getmethod' then
            if func.name.type == 'getmethod' then
                local finish = func.keyword[2]
                params = {
                    type = 'funcargs',
                    start = finish,
                    finish = finish,
                    parent = func,
                }
                params[1] = createLocal({
                    start = finish,
                    finish = finish,
                    parent = params,
                    [1] = 'self',
                }) --[[@as parser.object.self]]
                params[1].type = 'self'
            end
        end

        if hasLeftParen then
            local parenLeft = Token.left()
            Token.next()
            params = parseParams(params)
            params.start = parenLeft
            params.finish = lastRightPosition()
            params.parent = func
            func.args = params
            skipSpace(true)
            if Token.get(')') then
                func.finish = Token.right()
                func.bstart = func.finish
                if params then
                    params.finish = func.finish
                end
                Token.next()
                skipSpace(true)
            else
                func.finish = lastRightPosition()
                func.bstart = func.finish
                if params then
                    params.finish = func.finish
                end
                Error.missSymbol(')')
            end
        else
            Error.missSymbol('(')
        end

        P.Actions()
        Chunk.pop()
        func.bfinish = Token.left()
        parseEnd(func)
        Chunk.localCount = lastLocalCount

        return func
    end

    --- @return parser.object.lambda?
    function P.Lambda()
        -- FIXME: Use something other than nonstandardSymbol to check for lambda support
        if not (State.options.nonstandardSymbol['|lambda|'] and Token.get('|', '||')) then
            return
        end

        local isDoublePipe = Token.get('||')
        local lambdaLeft, lambdaRight = Token.left(), Token.right()
        --- @type parser.object.lambda
        local lambda = {
            type = 'function',
            start = lambdaLeft,
            finish = lambdaRight,
            bstart = lambdaRight,
            keyword = { lambdaLeft, lambdaRight },
            hasReturn = true,
        }
        Token.next()
        local pipeLeft, pipeRight = Token.left(), Token.right()
        skipSpace(true)
        local params
        local LastLocalCount = Chunk.localCount
        -- if nonstandardSymbol for '||' is true it is possible for token to be || when there are no params
        if isDoublePipe then
            params = {
                start = pipeLeft,
                finish = pipeRight,
                parent = lambda,
                type = 'funcargs',
            }
        else
            -- fake chunk to store locals
            Chunk.localCount = 0
            Chunk.push(lambda)
            params = parseParams(nil, true)
            params.start = pipeLeft
            params.finish = lastRightPosition()
            params.parent = lambda
            lambda.args = params
            skipSpace()
            if Token.get('|') then
                pipeRight = Token.right()
                lambda.finish = pipeRight
                lambda.bstart = pipeRight
                if params then
                    params.finish = pipeRight
                end
                Token.next()
                skipSpace()
            else
                lambda.finish = lastRightPosition()
                lambda.bstart = lambda.finish
                if params then
                    params.finish = lambda.finish
                end
                Error.missSymbol('|')
            end
        end
        local child = P.Exp()

        -- Drop fake chunk
        Chunk.drop()

        if child then
            -- create dummy return
            --- @type parser.object.return
            local rtn = {
                type = 'return',
                start = child.start,
                finish = child.finish,
                parent = lambda,
                [1] = child,
            }
            child.parent = rtn
            lambda[1] = rtn
            lambda.returns = { rtn }
            lambda.finish = child.finish
            lambda.keyword[3] = child.finish
            lambda.keyword[4] = child.finish
        else
            lambda.finish = lastRightPosition()
            Error.missExp()
        end
        lambda.bfinish = Token.left()
        Chunk.localCount = LastLocalCount
        return lambda
    end
end

--- @param source parser.object.expr
--- @return parser.object.expr
local function checkNeedParen(source)
    if not Token.get('.', ':') then
        return source
    end

    local exp = P.Simple(source, false)
    if exp == source then
        return exp
    end

    Error.push({
        type = 'NEED_PAREN',
        at = source,
        fix = {
            title = 'FIX_ADD_PAREN',
            {
                start = source.start,
                finish = source.start,
                text = '(',
            },
            {
                start = source.finish,
                finish = source.finish,
                text = ')',
            },
        },
    })

    return exp
end

function P.TableExpr()
    local r = P.Table()
    if r then
        return checkNeedParen(r)
    end
end

function P.StringExpr()
    local r = P.String()
    if r then
        return checkNeedParen(r)
    end
end

function P.NameExpr()
    local node = P.Name()
    if not node then
        return
    end
    local nameNode = resolveName(node)
    if nameNode then
        return P.Simple(nameNode, false)
    end
end

--- @return parser.object.expr?
function P.ExprUnit()
    return P.ParenExpr()
        or P.TableExpr()
        or P.StringExpr()
        or P.Varargs()
        or P.Number()
        or P.Nil()
        or P.Boolean()
        or P.Function()
        or P.Lambda()
        or P.NameExpr()
end

do -- P.BinaryOp
    local BinaryActionAlias = {
        ['='] = '==',
    }

    local BinaryAlias = {
        ['&&'] = 'and',
        ['||'] = 'or',
        ['!='] = '~=',
    }

    local BinarySymbol = {
        ['or'] = 1,
        ['and'] = 2,
        ['<='] = 3,
        ['>='] = 3,
        ['<'] = 3,
        ['>'] = 3,
        ['~='] = 3,
        ['=='] = 3,
        ['|'] = 4,
        ['~'] = 5,
        ['&'] = 6,
        ['<<'] = 7,
        ['>>'] = 7,
        ['..'] = 8,
        ['+'] = 9,
        ['-'] = 9,
        ['*'] = 10,
        ['//'] = 10,
        ['/'] = 10,
        ['%'] = 10,
        ['^'] = 12,
    }

    --- @param level integer # op level must greater than this level
    --- @return parser.binop?, integer?
    function P.BinaryOp(asAction, level)
        local token = Token.get()

        local symbol = (BinarySymbol[token] and token)
            or BinaryAlias[token]
            or (not asAction and BinaryActionAlias[token])

        if not symbol then
            return
        end

        if symbol == '//' and State.options.nonstandardSymbol['//'] then
            return
        end

        local myLevel = BinarySymbol[symbol]
        if level and myLevel < level then
            return
        end

        local op = initObj(symbol) --- @type parser.binop

        if not asAction then
            if token == '=' then
                Error.token('ERR_EQ_AS_ASSIGN', {
                    fix = { title = 'FIX_EQ_AS_ASSIGN', { text = '==' } },
                })
            end
        end

        if BinaryAlias[token] then
            if not State.options.nonstandardSymbol[token] then
                Error.token('ERR_NONSTANDARD_SYMBOL', {
                    info = {
                        symbol = symbol,
                    },
                    fix = {
                        title = 'FIX_NONSTANDARD_SYMBOL',
                        symbol = symbol,
                        {
                            text = symbol,
                        },
                    },
                })
            end
        end

        if Token.get('//', '<<', '>>') then
            if State.version ~= 'Lua 5.3' and State.version ~= 'Lua 5.4' then
                Error.token('UNEXPECT_SYMBOL', {
                    version = { 'Lua 5.3', 'Lua 5.4' },
                    info = {
                        version = State.version,
                    },
                })
            end
        end

        Token.next()

        return op, myLevel
    end
end

--- @return parser.object.expr?
function P.ExprUnary(asAction)
    local uop, uopLevel = unaryOP()
    if not uop then
        return P.ExprUnit()
    end

    skipSpace()

    local child = P.Exp(asAction, uopLevel)

    -- Precompute negative numbers
    if uop.type == '-' and child and (child.type == 'number' or child.type == 'integer') then
        --- @cast child parser.object.number|parser.object.integer
        child.start = uop.start
        child[1] = -child[1]
        return child
    end

    --- @type parser.object.unary
    local exp = {
        type = 'unary',
        op = uop,
        start = uop.start,
        finish = child and child.finish or uop.finish,
        [1] = child,
    }

    if child then
        child.parent = exp
    else
        Error.missExp()
    end

    return exp
end

local SymbolForward = {
    [01] = true,
    [02] = true,
    [03] = true,
    [04] = true,
    [05] = true,
    [06] = true,
    [07] = true,
    [08] = false,
    [09] = true,
    [10] = true,
    [11] = true,
    [12] = false,
}

--- @return parser.object.expr?
function P.Exp(asAction, level)
    local exp = P.ExprUnary(asAction)
    if not exp then
        return
    end

    while true do
        skipSpace()
        local bop, bopLevel = P.BinaryOp(asAction, level)
        if not bop then
            break
        end

        local child --- @type parser.object.expr?
        while true do
            skipSpace()
            local isForward = SymbolForward[bopLevel]
            child = P.Exp(asAction, isForward and (bopLevel + 0.5) or bopLevel)
            if child then
                break
            end
            if not skipUnknownSymbol() then
                Error.missExp()
                break
            end
        end

        --- @type parser.object.binop
        local bin = {
            type = 'binary',
            start = exp.start,
            finish = child and child.finish or bop.finish,
            op = bop,
            [1] = exp,
            [2] = child,
        }

        exp.parent = bin
        if child then
            child.parent = bin
        end
        exp = bin
    end

    return exp
end

--- @return parser.object?   first
--- @return parser.object?   second
--- @return parser.object[]? rest
local function parseSetValues()
    skipSpace()
    local first = P.Exp()
    if not first then
        return
    end
    skipSpace()
    if Token.get() ~= ',' then
        return first
    end
    Token.next()
    skipSeps()
    local second = P.Exp()
    if not second then
        Error.missExp()
        return first
    end
    skipSpace()
    if Token.get() ~= ',' then
        return first, second
    end
    Token.next()
    skipSeps()
    local third = P.Exp()
    if not third then
        Error.missExp()
        return first, second
    end

    local rest = { third }
    while true do
        skipSpace()
        if Token.get() ~= ',' then
            return first, second, rest
        end
        Token.next()
        skipSeps()
        local exp = P.Exp()
        if not exp then
            Error.missExp()
            return first, second, rest
        end
        rest[#rest + 1] = exp
    end
end

--- @return parser.object?   second
--- @return parser.object[]? rest
local function parseVarTails(parser, isLocal)
    if Token.get() ~= ',' then
        return
    end
    Token.next()
    skipSpace()
    local second = parser(true)
    if not second then
        Error.missName()
        return
    end
    if isLocal then
        createLocal(second, P.LocalAttrs())
    end
    skipSpace()
    if Token.get() ~= ',' then
        return second
    end
    Token.next()
    skipSeps()
    local third = parser(true)
    if not third then
        Error.missName()
        return second
    end
    if isLocal then
        createLocal(third, P.LocalAttrs())
    end
    local rest = { third }
    while true do
        skipSpace()
        if Token.get() ~= ',' then
            return second, rest
        end
        Token.next()
        skipSeps()
        local name = parser(true)
        if not name then
            Error.missName()
            return second, rest
        end
        if isLocal then
            createLocal(name, P.LocalAttrs())
        end
        rest[#rest + 1] = name
    end
end

local function bindValue(n, v, index, lastValue, isLocal, isSet)
    if isLocal then
        if v and v.special then
            addSpecial(v.special, n)
        end
    elseif isSet then
        n.type = GetToSetMap[n.type] or n.type
        if n.type == 'setlocal' then
            local loc = n.node
            if loc.attrs then
                Error.push({ type = 'SET_CONST', at = n })
            end
        end
    end
    if not v and lastValue then
        if lastValue.type == 'call' or lastValue.type == 'varargs' then
            v = lastValue
            if not v.extParent then
                v.extParent = {}
            end
        end
    end
    if v then
        if v.type == 'call' or v.type == 'varargs' then
            local select = {
                type = 'select',
                sindex = index,
                start = v.start,
                finish = v.finish,
                vararg = v,
            }
            if v.parent then
                v.extParent[#v.extParent + 1] = select
            else
                v.parent = select
            end
            v = select
        end
        n.value = v
        n.range = v.finish
        v.parent = n
    end
end

local function parseMultiVars(n1, parser, isLocal)
    local n2, nrest = parseVarTails(parser, isLocal)
    skipSpace()
    local v1, v2, vrest
    local isSet
    local max = 1
    if expectAssign(not isLocal) then
        v1, v2, vrest = parseSetValues()
        isSet = true
        if not v1 then
            Error.missExp()
        end
    end
    local index = 1
    bindValue(n1, v1, index, nil, isLocal, isSet)
    local lastValue = v1
    local lastVar = n1
    if n2 then
        max = 2
        if not v2 then
            index = 2
        end
        bindValue(n2, v2, index, lastValue, isLocal, isSet)
        lastValue = v2 or lastValue
        lastVar = n2
        Chunk.pushIntoCurrent(n2)
    end
    if nrest then
        for i = 1, #nrest do
            local n = nrest[i]
            local v = vrest and vrest[i]
            max = i + 2
            if not v then
                index = index + 1
            end
            bindValue(n, v, index, lastValue, isLocal, isSet)
            lastValue = v or lastValue
            lastVar = n
            Chunk.pushIntoCurrent(n)
        end
    end

    if isLocal then
        local effect = lastValue and lastValue.finish or lastVar.finish
        n1.effect = effect
        if n2 then
            n2.effect = effect
        end
        if nrest then
            for i = 1, #nrest do
                nrest[i].effect = effect
            end
        end
    end

    if v2 and not n2 then
        v2.redundant = {
            max = max,
            passed = 2,
        }
        Chunk.pushIntoCurrent(v2)
    end
    if vrest then
        for i = 1, #vrest do
            local v = vrest[i]
            if not nrest or not nrest[i] then
                v.redundant = {
                    max = max,
                    passed = i + 2,
                }
                Chunk.pushIntoCurrent(v)
            end
        end
    end

    return n1, isSet
end

local function skipFirstComment()
    if Token.get() ~= '#' then
        return
    end
    while true do
        Token.next()
        local token = Token.get()
        if not token then
            break
        end
        if NLMap[token] then
            skipNL()
            break
        end
    end
end

--- @param obj parser.object.block
--- @param x 'then' | 'do'
local function parseThenOrDo(obj, x)
    skipSpace()

    local wrong = x == 'then' and 'do' or 'then'

    local token = Token.get('then', 'do')
    if not token then
        Error.missSymbol(x)
        return
    end

    local left, right = Token.left(), Token.right()
    obj.finish = right
    obj.bstart = obj.finish
    obj.keyword[#obj.keyword + 1] = left
    obj.keyword[#obj.keyword + 1] = right

    if token == wrong then
        local err = x == 'then' and 'ERR_THEN_AS_DO' or 'ERR_DO_AS_THEN'
        Error.token(err, {
            fix = { title = 'FIX_THEN_AS_DO', { text = x } },
        })
    end

    Token.next()
end

--- @return parser.object.local?
function P.Local()
    if not Token.get('local') then
        return
    end

    local locPos = Token.left()
    Token.next()
    skipSpace()
    local word = peekWord()
    if not word then
        Error.missName()
        return
    end

    -- local function a()
    -- end
    local func = P.Function(true, true)
    if func then
        local name = func.name
        if name then
            func.name = nil
            name.value = func
            name.vstart = func.start
            name.range = func.finish
            name.locPos = locPos
            func.parent = name
            Chunk.pushIntoCurrent(name)
            return name
        end
        Error.missName(func.keyword[2])
        Chunk.pushIntoCurrent(func)
        return func
    end

    local name = P.Name(true)
    if not name then
        Error.missName()
        return
    end
    local loc = createLocal(name, P.LocalAttrs())
    loc.locPos = locPos
    loc.effect = math.maxinteger
    Chunk.pushIntoCurrent(loc)
    skipSpace()
    parseMultiVars(loc, P.Name, true)

    return loc
end

--- @return parser.object.do?
function P.Do()
    if not Token.get('do') then
        return
    end
    local obj = initBlock('do') --- @type parser.object.do
    Token.next()
    Chunk.pushIntoCurrent(obj)
    Chunk.push(obj)
    P.Actions()
    Chunk.pop()
    obj.bfinish = Token.left()
    parseEnd(obj)

    Chunk.localCount = Chunk.localCount - #(obj.locals or {})

    return obj
end

--- @return parser.object.return?
function P.Return()
    if not Token.get('return') then
        return
    end
    local left, right = Token.left(), Token.right()
    Token.next()
    skipSpace()

    local rtn --- @type parser.object.return
    local explist = P.ExpList(true)
    if explist then
        rtn = explist --[[@as parser.object.return]]
        rtn.type = 'return'
        rtn.start = left
    else
        rtn = {
            type = 'return',
            start = left,
            finish = right,
        }
    end

    Chunk.pushIntoCurrent(rtn)
    for block in Chunk.iter_rev() do
        if block.type == 'function' or block.type == 'main' then
            block.returns = block.returns or {}
            block.returns[#block.returns + 1] = rtn
            break
        end
    end

    for block in Chunk.iter_rev() do
        if
            block.type == 'ifblock'
            or block.type == 'elseifblock'
            or block.type == 'elseblock'
            or block.type == 'function'
        then
            block.hasReturn = true
            break
        end
    end

    return rtn
end

--- @return parser.object.label?
function P.Label()
    if not Token.get('::') then
        return
    end
    local left = Token.left()
    Token.next()
    skipSpace()
    local name = P.Name()
    skipSpace()

    if not name then
        Error.missName()
    end

    if Token.get('::') then
        Token.next()
    elseif name then
        Error.missSymbol('::')
    end

    if not name then
        return
    end

    local label = name --[[@as parser.object.label]]
    label.type = 'label'

    Chunk.pushIntoCurrent(label)

    local block = guide.getBlock(label)
    if block then
        block.labels = block.labels or {}
        local name0 = label[1]
        local olabel = guide.getLabel(block, name0)
        if olabel then
            if State.version == 'Lua 5.4' or block == guide.getBlock(olabel) then
                Error.push({
                    type = 'REDEFINED_LABEL',
                    at = label,
                    relative = {
                        {
                            olabel.start,
                            olabel.finish,
                        },
                    },
                })
            end
        end
        block.labels[name0] = label
    end

    if State.version == 'Lua 5.1' then
        Error.push({
            type = 'UNSUPPORT_SYMBOL',
            start = left,
            finish = lastRightPosition(),
            version = { 'Lua 5.2', 'Lua 5.3', 'Lua 5.4', 'LuaJIT' },
            info = {
                version = State.version,
            },
        })
        return
    end
    return label
end

--- @return parser.object.goto?
function P.Goto()
    if not (Token.get('goto') and isKeyWord('goto', Token.getPrev())) then
        return
    end

    local start = Token.left()
    Token.next()
    skipSpace()

    local name = P.Name()
    if not name then
        Error.missName()
        return
    end

    local action = name --[[@as parser.object.goto]]

    action.type = 'goto'
    action.keyStart = start

    for chunk in Chunk.iter_rev() do
        if chunk.type == 'function' or chunk.type == 'main' then
            chunk.gotos = chunk.gotos or {}
            chunk.gotos[#chunk.gotos + 1] = action
            break
        end
    end

    for chunk in Chunk.iter_rev() do
        if chunk.type == 'ifblock' or chunk.type == 'elseifblock' or chunk.type == 'elseblock' then
            chunk.hasGoTo = true
            break
        end
    end

    Chunk.pushIntoCurrent(action)
    return action
end

do -- P.If

  --- @param parent parser.object.if
  --- @return parser.object.ifblock?
  local function ifBlock(parent)
      if not Token.get('if') then
          return
      end
      --- @type parser.object.ifblock
      local obj = initBlock('ifblock')
      obj.parent = parent
      Token.next()
      skipSpace()
      local filter = P.Exp()
      if filter then
          obj.filter = filter
          obj.finish = filter.finish
          obj.bstart = obj.finish
          filter.parent = obj
      else
          Error.missExp()
      end

      parseThenOrDo(obj, 'then')

      Chunk.push(obj)
      P.Actions()
      Chunk.pop()
      obj.finish = Token.left()
      obj.bfinish = obj.finish
      Chunk.localCount = Chunk.localCount - #(obj.locals or {})
      return obj
  end

  --- @param parent parser.object.if
  --- @return parser.object.elseifblock?
  local function elseIfBlock(parent)
      if not Token.get('elseif') then
          return
      end
      local obj = initBlock('elseifblock') --- @type parser.object.elseifblock
      obj.parent = parent
      Token.next()
      skipSpace()
      local filter = P.Exp()
      if filter then
          obj.filter = filter
          obj.finish = filter.finish
          obj.bstart = obj.finish
          filter.parent = obj
      else
          Error.missExp()
      end
      parseThenOrDo(obj, 'then')
      Chunk.push(obj)
      P.Actions()
      Chunk.pop()
      obj.finish = Token.left()
      obj.bfinish = obj.finish
      Chunk.localCount = Chunk.localCount - #(obj.locals or {})
      return obj
  end

  --- @param parent parser.object.if
  --- @return parser.object.elseblock?
  local function elseBlock(parent)
      if not Token.get('else') then
          return
      end
      local obj = initBlock('elseblock') --- @type parser.object.elseblock
      obj.parent = parent
      Token.next()
      skipSpace()
      Chunk.push(obj)
      P.Actions()
      Chunk.pop()
      obj.finish = Token.left()
      obj.bfinish = obj.finish
      Chunk.localCount = Chunk.localCount - #(obj.locals or {})
      return obj
  end

  --- @return parser.object.if?
  function P.If()
      local token = Token.get('if', 'elseif', 'else')
      if not token then
          return
      end

      local obj = initBlock('if') --- @type parser.object.if
      Chunk.pushIntoCurrent(obj)

      if token ~= 'if' then
          Error.missSymbol('if', obj.keyword[1], obj.keyword[1])
      end

      local hasElse
      while true do
          local child = ifBlock(obj) or elseIfBlock(obj) or elseBlock(obj)
          if not child then
              break
          end
          if hasElse then
              Error.push({ type = 'BLOCK_AFTER_ELSE', at = child })
          end
          if child.type == 'elseblock' then
              hasElse = true
          end
          obj[#obj + 1] = child
          obj.finish = child.finish
          skipSpace()
      end

      parseEnd(obj)

      return obj
  end

end

do -- P.For

    --- @param action parser.object.for
    --- @param nameOrList parser.object.forlist|parser.object.name?
    --- @return parser.object.loop?
    local function forLoop(action, nameOrList)
        if not expectAssign() then
            return
        end

        local loop = action --[[@as parser.object.loop]]
        loop.type = 'loop'
        loop.stateVars = 3

        skipSpace()
        local expList = P.ExpList()
        local name
        if nameOrList then
            if nameOrList.type == 'name' then
                --- @cast nameOrList parser.object.name
                name = nameOrList
            else
                --- @cast nameOrList -parser.object.name
                name = nameOrList[1]
            end
        end
        -- for x in ... uses 4 variables
        Chunk.localCount = Chunk.localCount + loop.stateVars
        if name then
            local loc = createLocal(name)
            loc.parent = loop
            loop.finish = name.finish
            loop.bstart = loop.finish
            loop.loc = loc
        end

        if expList then
            expList.parent = loop
            local value, max, step = expList[1], expList[2], expList[3]
            if value then
                value.parent = expList
                loop.init = value
                loop.finish = expList[#expList].finish
                loop.bstart = loop.finish
            end
            if max then
                max.parent = expList
                loop.max = max
                loop.finish = max.finish
                loop.bstart = loop.finish
            else
                Error.push({
                    type = 'MISS_LOOP_MAX',
                    start = lastRightPosition(),
                    finish = lastRightPosition(),
                })
            end
            if step then
                step.parent = expList
                loop.step = step
                loop.finish = step.finish
                loop.bstart = loop.finish
            end
        else
            Error.push({
                type = 'MISS_LOOP_MIN',
                start = lastRightPosition(),
                finish = lastRightPosition(),
            })
        end

        if loop.loc then
            loop.loc.effect = loop.finish
        end

        return loop
    end

    --- @param action parser.object.for
    --- @param nameOrList parser.object.forlist|parser.object.name?
    --- @return parser.object.in?
    local function forIn(action, nameOrList)
        if not Token.get('in') then
            return
        end

        local forin = action --[[@as parser.object.in]]
        forin.type = 'in'
        forin.stateVars = State.version == 'Lua 5.4' and 4 or 3
        local inLeft, inRight = Token.left(), Token.right()
        Token.next()
        skipSpace()

        local exps = P.ExpList()

        forin.finish = inRight
        forin.bstart = forin.finish
        forin.keyword[3] = inLeft
        forin.keyword[4] = inRight

        local list --- @type parser.object.forlist?
        if nameOrList and nameOrList.type == 'name' then
            --- @cast nameOrList parser.object.name
            list = {
                type = 'list',
                start = nameOrList.start,
                finish = nameOrList.finish,
                parent = forin,
                [1] = nameOrList,
            }
        else
            --- @cast nameOrList -parser.object.name
            list = nameOrList
        end

        if exps then
            local lastExp = exps[#exps]
            if lastExp then
                forin.finish = lastExp.finish
                forin.bstart = forin.finish
            end

            forin.exps = exps
            exps.parent = forin
            for i = 1, #exps do
                local exp = exps[i]
                exp.parent = exps
            end
        else
            Error.missExp()
        end

        Chunk.localCount = Chunk.localCount + forin.stateVars

        if list then
            local lastName = list[#list]
            list.range = lastName and lastName.range or inRight
            forin.keys = list
            for _, obj in ipairs(list) do
                -- TODO(lewis6991): type check bug
                --- @cast obj -string
                local loc = createLocal(obj)
                loc.parent = forin
                loc.effect = forin.finish
            end
        end

        return forin
    end

    --- @return parser.object.for|parser.object.loop|parser.object.in?
    function P.For()
        if not Token.get('for') then
            return
        end

        local action = initBlock('for') --- @type parser.object.for
        Token.next()
        Chunk.pushIntoCurrent(action)
        Chunk.push(action)
        skipSpace()
        local nameOrList = P.NameOrList(action)
        if not nameOrList then
            Error.missName()
        end
        skipSpace()

        local obj = forLoop(action, nameOrList) or forIn(action, nameOrList) or action

        if obj.type == 'for' then
            Error.missSymbol('in')
        end

        parseThenOrDo(obj, 'do')

        skipSpace()
        P.Actions()
        Chunk.pop()
        skipSpace()
        obj.bfinish = Token.left()
        parseEnd(obj)

        Chunk.localCount = Chunk.localCount - #(obj.locals or {})
        Chunk.localCount = Chunk.localCount - (obj.stateVars or 0)

        return obj
    end

end

--- @return parser.object.while?
function P.While()
    if not Token.get('while') then
        return
    end
    local action = initBlock('while') --- @type parser.object.while
    Token.next()

    skipSpace()
    local tokenNext = Token.get()
    local filter = tokenNext ~= 'do' and tokenNext ~= 'then' and P.Exp()
    if filter then
        action.filter = filter
        action.finish = filter.finish
        filter.parent = action
    else
        Error.missExp()
    end

    parseThenOrDo(action, 'do')
    Chunk.pushIntoCurrent(action)
    Chunk.push(action)
    skipSpace()
    P.Actions()
    Chunk.pop()
    skipSpace()
    action.bfinish = Token.left()
    parseEnd(action)
    Chunk.localCount = Chunk.localCount - #(action.locals or {})

    return action
end

--- @return parser.object.repeat?
function P.Repeat()
    if not Token.get('repeat') then
        return
    end
    local obj = initBlock('repeat') --- @type parser.object.repeat
    Token.next()
    Chunk.pushIntoCurrent(obj)
    Chunk.push(obj)
    skipSpace()
    P.Actions()
    skipSpace()

    local start, finish = Token.left(), Token.right()
    obj.bfinish = start
    if Token.get('until') then
        obj.finish = finish
        obj.keyword[#obj.keyword + 1] = start
        obj.keyword[#obj.keyword + 1] = finish
        Token.next()

        skipSpace()
        local filter = P.Exp()
        if filter then
            obj.filter = filter
            filter.parent = obj
        else
            Error.missExp()
        end
    else
        Error.missSymbol('until')
    end

    Chunk.pop()
    Chunk.localCount = Chunk.localCount - #(obj.locals or {})

    if obj.filter then
        obj.finish = obj.filter.finish
    end

    return obj
end

--- @return parser.object.break?
function P.Break()
    if
        not Token.get('break')
        and not (Token.get('continue') and State.options.nonstandardSymbol['continue'])
    then
        return
    end
    --- @type parser.object.break
    local action = initObj('break') --- @as parser.object.break

    Token.next()
    skipSpace()

    local ok
    for chunk in Chunk.iter_rev() do
        local ty = chunk.type
        if ty == 'function' then
            break
        elseif ty == 'while' or ty == 'in' or ty == 'loop' or ty == 'repeat' or ty == 'for' then
            chunk.breaks = chunk.breaks or {}
            chunk.breaks[#chunk.breaks + 1] = action
            ok = true
            break
        end
    end

    for chunk in Chunk.iter_rev() do
        local ty = chunk.type
        if ty == 'ifblock' or ty == 'elseifblock' or ty == 'elseblock' then
            chunk.hasBreak = true
            break
        end
    end

    if not ok and Mode == 'Lua' then
        Error.push({ type = 'BREAK_OUTSIDE', at = action })
    end

    Chunk.pushIntoCurrent(action)
    return action
end

--- function a()
--- end
--- @return parser.object.function|parser.object.setlocal|parser.object.setmethod|parser.object.setindex|parser.object.setfield
function P.FunctionAction()
    local func = P.Function(false, true)
    if func then
        local name = func.name
        if name then
            func.name = nil
            name.type = GetToSetMap[name.type]
            name.value = func
            name.vstart = func.start
            name.range = func.finish
            func.parent = name
            if name.type == 'setlocal' and name.node.attrs then
                Error.push({ type = 'SET_CONST', at = name })
            end
            Chunk.pushIntoCurrent(name)
            return name
        end

        Error.missName(func.keyword[2])
        Chunk.pushIntoCurrent(func)
        return func
    end
end

--- @return parser.object.expr?
function P.ExprAction()
    local exp = P.Exp(true)
    if not exp then
        return
    end

    Chunk.pushIntoCurrent(exp)
    if GetToSetMap[exp.type] then
        skipSpace()
        local isLocal
        if exp.type == 'getlocal' and exp[1] == State.ENVMode then
            exp.special = nil
            -- TODO: need + 1 at the end
            Chunk.localCount = Chunk.localCount - 1
            local loc = createLocal(exp, P.LocalAttrs())
            loc.locPos = exp.start
            loc.effect = math.maxinteger
            isLocal = true
            skipSpace()
        end
        local action, isSet = parseMultiVars(exp, P.Exp, isLocal)
        if isSet or action.type == 'getmethod' then
            return action
        end
    end

    if exp.type == 'call' then
        if exp.hasExit then
            for block in Chunk.iter_rev() do
                if
                    block.type == 'ifblock'
                    or block.type == 'elseifblock'
                    or block.type == 'elseblock'
                    or block.type == 'function'
                then
                    block.hasExit = true
                    break
                end
            end
        end
        return exp
    end

    if exp.type == 'binary' then
        if GetToSetMap[exp[1].type] then
            local op = exp.op
            if op.type == '==' then
                Error.push({
                    type = 'ERR_ASSIGN_AS_EQ',
                    at = op,
                    fix = {
                        title = 'FIX_ASSIGN_AS_EQ',
                        {
                            start = op.start,
                            finish = op.finish,
                            text = '=',
                        },
                    },
                })
                return
            end
        end
    end

    Error.push({ type = 'EXP_IN_ACTION', at = exp })

    return exp
end

--- @return parser.object.action?
function P.Action()
    return P.Label()
        or P.Local()
        or P.If()
        or P.For()
        or P.Do()
        or P.Return()
        or P.Break()
        or P.While()
        or P.Repeat()
        or P.Goto()
        or P.FunctionAction()
        or P.ExprAction()
end

--- @return parser.object.main
function P.Lua()
    --- @type parser.object.main
    local main = { type = 'main', start = 0, finish = 0, bstart = 0 }
    Chunk.push(main)
    createLocal({
        type = 'local',
        start = -1,
        finish = -1,
        effect = -1,
        parent = main,
        tag = '_ENV',
        special = '_G',
        [1] = State.ENVMode,
    })
    Chunk.localCount = 0
    skipFirstComment()
    while true do
        P.Actions()
        if not Token.get() then
            break
        end
        unknownSymbol()
        Token.next()
    end
    Chunk.pop()
    main.finish = getPosition(#Lua, 'right')
    main.bfinish = main.finish

    return main
end

--- @param lua string
--- @param version string
--- @param options table
local function initState(lua, version, options)
    Lua = lua
    Line = 0
    LineOffset = 1
    LastTokenFinish = 0
    Token.init(lua)

    ---@type parser.state
    local state = {
        version = version,
        lua = lua,
        errs = {},
        comms = {},
        lines = {
            [0] = 1,
            size = #lua,
        },
        options = options or {},
        ENVMode = (version == 'Lua 5.1' or version == 'LuaJIT') and '@fenv' or '_ENV',
    }

    if not state.options.nonstandardSymbol then
        state.options.nonstandardSymbol = {}
    end

    State = state

    --- @param err parser.state.err
    --- @return parser.state.err?
    Error.push = function(err)
        local errs = state.errs
        err.finish = (err.at or err).finish
        err.start = (err.at or err).start

        if err.finish < err.start then
            err.finish = err.start
        end
        local last = errs[#errs]
        if last then
            if last.start <= err.start and last.finish >= err.finish then
                return
            end
        end
        err.level = err.level or 'Error'
        errs[#errs + 1] = err
        return err
    end
    Chunk = require('parser.chunk')(Error.push)
end

--- @param lua string
--- @param mode 'Lua' | 'Nil' | 'Boolean' | 'String' | 'Number' | 'Name' | 'Exp' | 'Action'
--- @param version string
--- @param options table
return function(lua, mode, version, options)
    Mode = mode
    initState(lua, version, options)
    skipSpace()

    State.ast = assert(P[mode])()

    if State.ast then
        State.ast.state = State
    end

    while Token.get() do
        unknownSymbol()
        Token.next()
    end

    return State
end
