local tokens = require('parser.tokens')
local guide = require('parser.guide')

--- @alias parser.position integer

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

local CharMapNumber = stringToCharMap('0-9')
local CharMapN16 = stringToCharMap('xX')
local CharMapN2 = stringToCharMap('bB')
local CharMapE10 = stringToCharMap('eE')
local CharMapE16 = stringToCharMap('pP')
local CharMapSign = stringToCharMap('+-')
-- local CharMapSB      = stringToCharMap 'ao|~&=<>.*/%^+-'
-- local CharMapSU      = stringToCharMap 'n#~!-'
-- local CharMapSimple  = stringToCharMap '.:([\'"{'
local CharMapStrSH = stringToCharMap('\'"`')
local CharMapStrLH = stringToCharMap('[')
local CharMapTSep = stringToCharMap(',;')
local CharMapWord = stringToCharMap('_a-zA-Z\x80-\xff')

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

local NLMap = {
  ['\n'] = true,
  ['\r'] = true,
  ['\r\n'] = true,
}

local LineMulti = 10000

-- goto is processed separately
local KeyWord = {
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

local UnarySymbol = {
  ['not'] = 11,
  ['#'] = 11,
  ['~'] = 11,
  ['-'] = 11,
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

local BinaryAlias = {
  ['&&'] = 'and',
  ['||'] = 'or',
  ['!='] = '~=',
}

local BinaryActionAlias = {
  ['='] = '==',
}

local UnaryAlias = {
  ['!'] = 'not',
}

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

--- Nodes

--- @alias parser.object.union
--- | parser.object.block
--- | parser.object.expr
--- | parser.object.forlist
--- | parser.object.goto
--- | parser.object.local
--- | parser.object.main
--- | parser.object.name

--- @class parser.object.base
--- @field start integer
--- @field finish integer
--- @field parent? parser.object.union
--- @field special? string
--- @field state? parser.state

--- @class parser.object.forlist : parser.object.base
--- @field type 'list'
--- @field [integer] parser.object.name

--- @class parser.object.goto : parser.object.base
--- @field type 'goto'
--- @field node? parser.object.label

--- @class parser.object.localattrs : parser.object.base
--- @field type 'localattrs'
--- @field parent? parser.object.union
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
--- @field [1] string Name of local variable

--- @class parser.object.main : parser.object.base
--- @field type 'main'

--- @class parser.object.name : parser.object.base
--- @field type 'name'
--- @field [1] string value
---

--- Expressions

--- @alias parser.object.expr
--- | parser.object.binop
--- | parser.object.boolean
--- | parser.object.explist
--- | parser.object.getglobal
--- | parser.object.getlocal
--- | parser.object.label
--- | parser.object.number
--- | parser.object.paren
--- | parser.object.string
--- | parser.object.unary
--- | parser.object.varargs

--- @class parser.binop
--- @field type 'or' | 'and' | '<=' | '>=' | '<' | '>' | '~=' | '==' | '|' | '~' | '&' | '<<' | '>>' | '..' | '+' | '-' | '*' | '//' | '/' | '%' | '^'
--- @field start integer
--- @field finish integer

--- @class parser.object.binop : parser.object.base
--- @field type 'binary
--- @field op parser.binop
--- @field [1] parser.object.expr
--- @field [2] parser.object.expr

--- @class parser.object.boolean : parser.object.base
--- @field type 'boolean'
--- @field [1] boolean value

--- @class parser.object.explist : parser.object.base
--- @field type 'list'
--- @field [integer] parser.object.expr

--- @class parser.object.getglobal : parser.object.base
--- @field type 'getglobal'
--- @field node parser.object.local

--- @class parser.object.getlocal : parser.object.base
--- @field type 'getlocal'
--- @field node parser.object.local

--- @class parser.object.label : parser.object.base
--- @field type 'label'
--- @field ref? parser.object.goto[] References to label
--- @field [1] string value

--- @class parser.object.number : parser.object.base
--- @field type 'number'|'integer'

--- @class parser.object.paren : parser.object.base
--- @field type 'paren'
--- @field exp? parser.object.expr

--- @class parser.object.string : parser.object.base
--- @field type 'string'
--- @field escs? (string|integer)[] [int, int, string, int, int, string, ...]
--- @field [1] string value
--- @field [2] integer string delimiter

--- @class parser.object.unary : parser.object.base
--- @field type 'unary'
--- @field [1] parser.object.expr?

--- @class parser.object.varargs : parser.object.base
--- @field type 'varargs'
--- @field node? unknown

--- Blocks

--- @alias parser.object.block
--- | parser.object.do
--- | parser.object.if
--- | parser.object.ifblock
--- | parser.object.for
--- | parser.object.loop
--- | parser.object.in
--- | parser.object.while

--- @class parser.object.block.common : parser.object.base
--- @field parent? parser.object.block
--- @field labels? table<string,parser.object.label>
--- @field locals parser.object.local[]
--- @field gotos?
--- @field bstart integer Block start
--- @field [integer] parser.object.block

--- @class parser.object.do : parser.object.block.common
--- @field type 'do'

--- Blocks: If

--- @class parser.object.if : parser.object.block.common
--- @field type 'if'

--- @class parser.object.ifblock : parser.object.block.common
--- @field type 'ifblock'
--- @field parent parser.object.if
--- @field start integer
--- @field filter? parser.object? Condition of if block
--- @field keyword [integer,integer]

--- Blocks: Loops

--- @class parser.object.for : parser.object.block.common
--- @field type 'for'
--- @field keyword [integer,integer]

--- @class parser.object.loop : parser.object.block.common
--- @field type 'loop'
--- @field keyword [integer,integer]
--- @field loc? parser.object.local
--- @field init? parser.object.expr
--- @field max? parser.object.expr
--- @field step? parser.object.expr

--- @class parser.object.in : parser.object.block.common
--- @field type 'in'
--- @field keyword [integer,integer, integer, integer]
--- @field exps parser.object.explist
--- @field keys parser.object.forlist

--- @class parser.object.while : parser.object.block.common
--- @field type 'while'
--- @field keyword [integer,integer]
--- @field filter? parser.object.expr

--- State

--- @class parser.state.err
--- @field at? parser.object.base
--- @field type string
--- @field start? parser.position
--- @field finish? parser.position
--- @field info? parser.info
--- @field fix? parser.fix
--- @field version? string[]|string
--- @field level? string | 'Error' | 'Warning'

--- @class parser.fix
--- @field title string
--- @field symbol? string
--- @field [1] {start:integer, finish: integer, test: string}

--- @class parser.info
--- @field symbol? string
--- @field version? string

--- @class parser.state
--- @field lua? string
--- @field uri? string
--- @field lines integer[]
--- @field version string
--- @field options table
--- @field ENVMode '@fenv' | '_ENV'
--- @field errs parser.state.err[]
--- @field specials? table<string,parser.object.base[]>
--- @field ast? parser.object.union

local LocalLimit = 200

local State --- @type parser.state
local Lua --- @type string
local Line --- @type integer
local LineOffset --- @type integer
local Mode
local LastTokenFinish, LocalCount, LocalLimited

--- @param offset integer
--- @param leftOrRight 'left'|'right'
local function getPosition(offset, leftOrRight)
  if not offset or offset > #Lua then
    return LineMulti * Line + #Lua - LineOffset + 1
  end
  if leftOrRight == 'left' then
    return LineMulti * Line + offset - LineOffset
  else
    return LineMulti * Line + offset - LineOffset + 1
  end
end

local Token = {
  Tokens = nil, --- @type (integer|string)[]
  Index = nil, --- @type integer
}

do -- Token interface
  --- @return string?
  function Token.get()
    return Token.Tokens[Token.Index + 1] --[[@as string]]
  end

  --- @return string?
  function Token.getPrev()
    return Token.Tokens[Token.Index - 1] --[[@as string]]
  end

  --- @return integer?
  function Token.peek()
    return Token.Tokens[Token.Index + 3] --[[@as integer]]
  end

  function Token.next()
    Token.Index = Token.Index + 2
  end

  --- @return integer?
  function Token.peekPos()
    return Token.Tokens[Token.Index + 2] --[[@as integer]]
  end

  --- @return integer
  function Token.getPos()
    return Token.Tokens[Token.Index] --[[@as integer]]
  end

  --- @return integer
  function Token.getPrevPos()
    return Token.Tokens[Token.Index - 2] --[[@as integer]]
  end

  function Token.getWithPos()
    local token = Token.get()
    if not token then
      return
    end
    local startPos = getPosition(Token.getPos(), 'left')
    local finish = getPosition(Token.getPos() + #token - 1, 'right')
    return token, startPos, finish
  end
end

--- @type fun(err:parser.state.err):parser.state.err?
local pushError

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
  return Token.getWithPos()
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

local Error = {}

--- @param ty string
--- @param attr? {start?:integer, finish?:integer, fix?:parser.fix[]}
function Error.token(ty, attr)
  attr = attr or {}
  --- @cast attr parser.state.err
  attr.type = ty
  if not attr.start or not attr.finish then
    local _, start, finish = assert(Token.getWithPos())
    attr.start = attr.start or start
    attr.finish = attr.finish or finish
  end

  for _, fix in ipairs(attr.fix or {}) do
    if fix[1] then
      fix[1].start = fix[1].start or attr.start
      fix[1].finish = fix[1].finish or attr.finish
    end
  end

  pushError(attr)
end

--- @param symbol string
--- @param start? integer
--- @param finish? integer
function Error.missSymbol(symbol, start, finish)
  pushError({
    type = 'MISS_SYMBOL',
    start = start or lastRightPosition(),
    finish = finish or start or lastRightPosition(),
    info = {
      symbol = symbol,
    },
  })
end

function Error.missExp()
  pushError({
    type = 'MISS_EXP',
    start = lastRightPosition(),
    finish = lastRightPosition(),
  })
end

--- @param pos? integer
function Error.missName(pos)
  pushError({
    type = 'MISS_NAME',
    start = pos or lastRightPosition(),
    finish = pos or lastRightPosition(),
  })
end

--- @param relatedStart integer
--- @param relatedFinish integer
function Error.missEnd(relatedStart, relatedFinish)
  pushError({
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
  pushError({
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
  if NLMap[token] then
    local prevToken = Token.getPrev()
    if prevToken and not NLMap[prevToken] then
      LastTokenFinish = getPosition(Token.getPrevPos() + #prevToken - 1, 'right')
    end
    Line = Line + 1
    LineOffset = Token.getPos() + #token
    Token.next()
    State.lines[Line] = LineOffset
    return true
  end
  return false
end

local function getSavePoint()
  local index = Token.Index
  local line = Line
  local lineOffset = LineOffset
  local errs = State.errs
  local errCount = #errs
  return function()
    Token.Index = index
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

  local finishOffset = string.find(Lua, finishMark, start, true)
  if not finishOffset then
    finishOffset = #Lua + 1
    miss = true
  end

  local stringResult = start and Lua:sub(start, finishOffset - 1) or ''

  local lastLN = stringResult:find('[\r\n][^\r\n]*$')
  if lastLN then
    local result = stringResult:gsub('\r\n?', '\n')
    stringResult = result
  end

  if finishMark == ']]' and State.version == 'Lua 5.1' then
    local nestOffset = Lua:find('[[', start, true)
    if nestOffset and nestOffset < finishOffset then
      fastForwardToken(nestOffset)
      local nestStartPos = getPosition(nestOffset, 'left')
      local nestFinishPos = getPosition(nestOffset + 1, 'right')
      pushError({
        type = 'NESTING_LONG_MARK',
        start = nestStartPos,
        finish = nestFinishPos,
      })
    end
  end

  fastForwardToken(finishOffset + #finishMark)
  if miss then
    local pos = getPosition(finishOffset - 1, 'right')
    pushError({
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

--- @return parser.object.string?
local function parseLongString()
  local start, finish, mark = string.find(Lua, '^(%[%=*%[)', Token.getPos())
  if not start then
    return
  end
  fastForwardToken(finish + 1)
  local startPos = getPosition(start, 'left')
  local finishMark = string.gsub(mark, '%[', ']')
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
  pushError({
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
    local left = getPosition(start, 'left')
    local chead = false
    if token == '//' then
      chead = true
      pushCommentHeadError(left)
    end
    Token.next()
    local longComment = start + 2 == Token.getPos() and parseLongString()
    if longComment then
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
  end
  if token == '/*' then
    local start = Token.getPos()
    local left = getPosition(start, 'left')
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

local function skipSpace(isAction)
  repeat
  until not skipNL() and not skipComment(isAction)
end

local function expectAssign(isAction)
  local token = Token.get()
  if token == '=' then
    Token.next()
    return true
  end
  if token == '==' then
    local _, left, right = Token.getWithPos()
    Error.token('ERR_ASSIGN_AS_EQ', {
      fix = {
        title = 'FIX_ASSIGN_AS_EQ',
        {
          text = '=',
        },
      },
    })
    Token.next()
    return true
  end
  if isAction then
    if
      token == '+='
      or token == '-='
      or token == '*='
      or token == '/='
      or token == '%='
      or token == '^='
      or token == '//='
      or token == '|='
      or token == '&='
      or token == '>>='
      or token == '<<='
    then
      if not State.options.nonstandardSymbol[token] then
        unknownSymbol()
      end
      Token.next()
      return true
    end
  end
  return false
end

--- @return parser.object.localattrs?
local function parseLocalAttrs()
  --- @type parser.object.localattrs?
  local attrs
  while true do
    skipSpace()
    local token = Token.get()
    if token ~= '<' then
      break
    end
    if not attrs then
      attrs = {
        type = 'localattrs',
      }
    end
    local _, start, finish = assert(Token.getWithPos())
    --- @type parser.object.localattr
    local attr = {
      type = 'localattr',
      parent = attrs,
      start = start,
      finish = finish,
    }
    attrs[#attrs + 1] = attr
    Token.next()
    local token = Token.get()
    skipSpace()

    local word, wstart, wfinish = peekWord()
    if word then
      assert(wstart and wfinish)
      attr[1] = word
      attr.finish = wfinish
      Token.next()
      if word ~= 'const' and word ~= 'close' then
        pushError({
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

    local token, start, finish = Token.getWithPos()

    if token == '>' then
      attr.finish = assert(finish)
      Token.next()
    elseif token == '>=' then
      attr.finish = assert(finish)
      Error.token('MISS_SPACE_BETWEEN')
      Token.next()
    else
      Error.missSymbol('>')
    end

    if State.version ~= 'Lua 5.4' then
      pushError({
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

--- @class parser.Chunk
--- @field [integer] parser.object.block
local Chunk = {}

do -- Chunk interface
  function Chunk.push(chunk)
    Chunk[#Chunk + 1] = chunk
  end

  ---@param x parser.object.block
  function Chunk.pushIntoCurrent(x)
    local chunk = Chunk[#Chunk]
    if chunk then
      chunk[#chunk + 1] = x
      x.parent = chunk
    end
  end

  function Chunk.get()
    return Chunk[#Chunk]
  end

  --- @param label parser.object.label
  --- @param obj parser.object.goto
  local function resolveLable(label, obj)
    label.ref = label.ref or {}
    label.ref[#label.ref + 1] = obj
    obj.node = label

    -- If there is a local variable declared between goto and label,
    -- and used after label, it is counted as a syntax error

    -- If label is declared before goto, there will be no local variables declared in the middle
    if obj.start > label.start then
      return
    end

    local block = guide.getBlock(obj)
    local locals = block and block.locals

    for _, loc in ipairs(locals or {}) do
      local should_break = (function()
        -- Check that the local variable declaration position is between goto and label
        if loc.start < obj.start or loc.finish > label.finish then
          return
        end
        -- Check where local variables are used after label
        local refs = loc.ref
        if not refs then
          return
        end
        for j = 1, #refs do
          local ref = refs[j]
          if ref.finish > label.finish then
            pushError({
              type = 'JUMP_LOCAL_SCOPE',
              at = obj,
              info = {
                loc = loc[1],
              },
              relative = {
                {
                  start = label.start,
                  finish = label.finish,
                },
                {
                  start = loc.start,
                  finish = loc.finish,
                },
              },
            })
            return true
          end
        end
      end)()

      if should_break then
        break
      end
    end
  end

  local function resolveGoTo(gotos)
    for i = 1, #gotos do
      local action = gotos[i]
      local label = guide.getLabel(action, action[1])
      if label then
        resolveLable(label, action)
      else
        pushError({
          type = 'NO_VISIBLE_LABEL',
          at = action,
          info = {
            label = action[1],
          },
        })
      end
    end
  end

  function Chunk.pop()
    local chunk = Chunk[#Chunk]
    if chunk.gotos then
      resolveGoTo(chunk.gotos)
      chunk.gotos = nil
    end
    local lastAction = chunk[#chunk]
    if lastAction then
      chunk.finish = lastAction.finish
    end
    Chunk[#Chunk] = nil
  end

  function Chunk.clear()
    for i = 1, #Chunk do
      Chunk[i] = nil
    end
  end

  --- @param x parser.object.local
  function Chunk.addLocal(x)
    -- Add local to current chunk
    local chunk = Chunk[#Chunk]
    if chunk then
      chunk.locals = chunk.locals or {}
      local locals = chunk.locals
      locals[#locals + 1] = x
      LocalCount = LocalCount + 1
      if not LocalLimited and LocalCount > LocalLimit then
        LocalLimited = true
        pushError({ type = 'LOCAL_LIMIT', at = x })
      end
    end
  end
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

local function parseNil()
  if Token.get() ~= 'nil' then
    return
  end
  local offset = Token.getPos()
  Token.next()
  return {
    type = 'nil',
    start = getPosition(offset, 'left'),
    finish = getPosition(offset + 2, 'right'),
  }
end

--- @return parser.object.boolean?
local function parseBoolean()
  local word = Token.get()
  if word ~= 'true' and word ~= 'false' then
    return
  end
  local _, start, finish = Token.getWithPos()
  Token.next()
  return {
    type = 'boolean',
    start = start,
    finish = finish,
    [1] = word == 'true' and true or false,
  }
end

local function parseStringUnicode()
  local offset = Token.getPos() + 1
  if Lua:sub(offset, offset) ~= '{' then
    local pos = getPosition(offset, 'left')
    Error.missSymbol('{', pos)
    return nil, offset
  end
  local leftPos = getPosition(offset, 'left')
  local x16 = string.match(Lua, '^%w*', offset + 1)
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
    pushError({
      type = 'UTF8_SMALL',
      start = leftPos,
      finish = rightPos,
    })
    return '', offset
  end
  if State.version ~= 'Lua 5.3' and State.version ~= 'Lua 5.4' and State.version ~= 'LuaJIT' then
    pushError({
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
        pushError({
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
      pushError({
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
      pushError({
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

local stringPool = {}

--- @return parser.object.string
local function parseShortString()
  local mark = Token.get()
  local startOffset = Token.getPos()
  local startPos = getPosition(startOffset, 'left')
  Token.next()
  local stringIndex = 0
  local currentOffset = startOffset + 1
  local escs = {}
  while true do
    if
      (function()
        local token = Token.get()
        if not token then
          stringIndex = stringIndex + 1
          stringPool[stringIndex] = Lua:sub(currentOffset or -1)
          Error.missSymbol(mark)
          return true
        elseif token == mark then
          stringIndex = stringIndex + 1
          stringPool[stringIndex] = Lua:sub(currentOffset, Token.getPos() - 1)
          Token.next()
          return true
        elseif NLMap[token] then
          stringIndex = stringIndex + 1
          stringPool[stringIndex] = Lua:sub(currentOffset, Token.getPos() - 1)
          Error.missSymbol(mark)
          return true
        elseif token == '\\' then
          stringIndex = stringIndex + 1
          stringPool[stringIndex] = Lua:sub(currentOffset, Token.getPos() - 1)
          currentOffset = Token.getPos()
          Token.next()
          if not Token.getPos() then
            return
          end
          local escLeft = getPosition(currentOffset, 'left')
          -- has space?
          if Token.getPos() - currentOffset > 1 then
            Error.token('ERR_ESC')
            escs[#escs + 1] = escLeft
            escs[#escs + 1] = getPosition(currentOffset + 1, 'right')
            escs[#escs + 1] = 'err'
            return
          end

          local tokenNext = Token.get():sub(1, 1)
          if EscMap[tokenNext] then
            stringIndex = stringIndex + 1
            stringPool[stringIndex] = EscMap[tokenNext]
            currentOffset = Token.getPos() + #tokenNext
            Token.next()
            escs[#escs + 1] = escLeft
            escs[#escs + 1] = escLeft + 2
            escs[#escs + 1] = 'normal'
            return
          elseif tokenNext == mark then
            stringIndex = stringIndex + 1
            stringPool[stringIndex] = mark
            currentOffset = Token.getPos() + #tokenNext
            Token.next()
            escs[#escs + 1] = escLeft
            escs[#escs + 1] = escLeft + 2
            escs[#escs + 1] = 'normal'
            return
          elseif tokenNext == 'z' then
            Token.next()
            repeat
            until not skipNL()
            currentOffset = Token.getPos()
            escs[#escs + 1] = escLeft
            escs[#escs + 1] = escLeft + 2
            escs[#escs + 1] = 'normal'
            return
          elseif CharMapNumber[tokenNext] then
            local numbers = Token.get():match('^%d+')
            if #numbers > 3 then
              numbers = string.sub(numbers, 1, 3)
            end
            currentOffset = Token.getPos() + #numbers
            fastForwardToken(currentOffset)
            local right = getPosition(currentOffset - 1, 'right')
            local byte = math.tointeger(numbers)
            if byte and byte <= 255 then
              stringIndex = stringIndex + 1
              stringPool[stringIndex] = string.char(byte)
            else
              pushError({
                type = 'ERR_ESC',
                start = escLeft,
                finish = right,
              })
            end
            escs[#escs + 1] = escLeft
            escs[#escs + 1] = right
            escs[#escs + 1] = 'byte'
            return
          elseif tokenNext == 'x' then
            local left = getPosition(Token.getPos() - 1, 'left')
            local x16 = Token.get():sub(2, 3)
            local byte = tonumber(x16, 16)
            if byte then
              currentOffset = Token.getPos() + 3
              stringIndex = stringIndex + 1
              stringPool[stringIndex] = string.char(byte)
            else
              currentOffset = Token.getPos() + 1
              pushError({
                type = 'MISS_ESC_X',
                start = getPosition(currentOffset, 'left'),
                finish = getPosition(currentOffset + 1, 'right'),
              })
            end
            local right = getPosition(currentOffset + 1, 'right')
            escs[#escs + 1] = escLeft
            escs[#escs + 1] = right
            escs[#escs + 1] = 'byte'
            if State.version == 'Lua 5.1' then
              pushError({
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
            return
          elseif tokenNext == 'u' then
            local str, newOffset = parseStringUnicode()
            if str then
              stringIndex = stringIndex + 1
              stringPool[stringIndex] = str
            end
            currentOffset = newOffset
            fastForwardToken(currentOffset - 1)
            local right = getPosition(currentOffset + 1, 'right')
            escs[#escs + 1] = escLeft
            escs[#escs + 1] = right
            escs[#escs + 1] = 'unicode'
            return
          elseif NLMap[tokenNext] then
            stringIndex = stringIndex + 1
            stringPool[stringIndex] = '\n'
            currentOffset = Token.getPos() + #tokenNext
            skipNL()
            escs[#escs + 1] = escLeft
            escs[#escs + 1] = escLeft + 1
            escs[#escs + 1] = 'normal'
            return
          end

          local right = getPosition(currentOffset + 1, 'right')
          pushError({ type = 'ERR_ESC', start = escLeft, finish = right })
          escs[#escs + 1] = escLeft
          escs[#escs + 1] = right
          escs[#escs + 1] = 'err'
        end
        Token.next()
      end)()
    then
      break
    end
  end

  local stringResult = table.concat(stringPool, '', 1, stringIndex)
  --- @type parser.object.string
  local str = {
    type = 'string',
    start = startPos,
    finish = lastRightPosition(),
    escs = #escs > 0 and escs or nil,
    [1] = stringResult,
    [2] = mark,
  }

  if mark == '`' then
    if not State.options.nonstandardSymbol[mark] then
      pushError({
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
  end

  return str
end

--- @return parser.object.string?
local function parseString()
  local c = Token.get()
  if CharMapStrSH[c] then
    return parseShortString()
  end
  if CharMapStrLH[c] then
    return parseLongString()
  end
end

local function parseNumber10(start)
  local integer = true
  local integerPart = string.match(Lua, '^%d*', start)
  local offset = start + #integerPart
  -- float part
  if string.sub(Lua, offset, offset) == '.' then
    local floatPart = string.match(Lua, '^%d*', offset + 1)
    integer = false
    offset = offset + #floatPart + 1
  end
  -- exp part
  local echar = Lua:sub(offset, offset)
  if CharMapE10[echar] then
    integer = false
    offset = offset + 1
    local nextChar = string.sub(Lua, offset, offset)
    if CharMapSign[nextChar] then
      offset = offset + 1
    end
    local exp = Lua:match('^%d*', offset)
    offset = offset + #exp
    if #exp == 0 then
      pushError({
        type = 'MISS_EXPONENT',
        start = getPosition(offset - 1, 'right'),
        finish = getPosition(offset - 1, 'right'),
      })
    end
  end
  return tonumber(Lua:sub(start, offset - 1)), offset, integer
end

local function parseNumber16(start)
  local integerPart = string.match(Lua, '^[%da-fA-F]*', start)
  local offset = start + #integerPart
  local integer = true
  -- float part
  if string.sub(Lua, offset, offset) == '.' then
    local floatPart = string.match(Lua, '^[%da-fA-F]*', offset + 1)
    integer = false
    offset = offset + #floatPart + 1
    if #integerPart == 0 and #floatPart == 0 then
      pushError({
        type = 'MUST_X16',
        start = getPosition(offset - 1, 'right'),
        finish = getPosition(offset - 1, 'right'),
      })
    end
  else
    if #integerPart == 0 then
      pushError({
        type = 'MUST_X16',
        start = getPosition(offset - 1, 'right'),
        finish = getPosition(offset - 1, 'right'),
      })
      return 0, offset
    end
  end
  -- exp part
  local echar = string.sub(Lua, offset, offset)
  if CharMapE16[echar] then
    integer = false
    offset = offset + 1
    local nextChar = string.sub(Lua, offset, offset)
    if CharMapSign[nextChar] then
      offset = offset + 1
    end
    local exp = string.match(Lua, '^%d*', offset)
    offset = offset + #exp
  end
  local n = tonumber(string.sub(Lua, start - 2, offset - 1))
  return n, offset, integer
end

local function parseNumber2(start)
  local bins = string.match(Lua, '^[01]*', start)
  local offset = start + #bins
  if State.version ~= 'LuaJIT' then
    pushError({
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
  local _, finish, word = string.find(Lua, '^([%.%w_\x80-\xff]+)', offset)
  if not finish then
    return offset
  end
  if integer then
    if string.upper(string.sub(word, 1, 2)) == 'LL' then
      if State.version ~= 'LuaJIT' then
        pushError({
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
        pushError({
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
      word = string.sub(word, offset)
    end
  end
  if word:sub(1, 1):upper() == 'I' then
    if State.version ~= 'LuaJIT' then
      pushError({
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
    pushError({
      type = 'MALFORMED_NUMBER',
      start = getPosition(offset, 'left'),
      finish = getPosition(finish, 'right'),
    })
  end
  return finish + 1
end

--- @return parser.object.number?
local function parseNumber()
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
  local firstChar = string.sub(Lua, offset, offset)
  if firstChar == '.' then
    number, offset = parseNumber10(offset)
    integer = false
  elseif firstChar == '0' then
    local nextChar = string.sub(Lua, offset + 1, offset + 1)
    if CharMapN16[nextChar] then
      number, offset, integer = parseNumber16(offset + 2)
    elseif CharMapN2[nextChar] then
      number, offset = parseNumber2(offset + 2)
      integer = true
    else
      number, offset, integer = parseNumber10(offset)
    end
  elseif CharMapNumber[firstChar] then
    number, offset, integer = parseNumber10(offset)
  else
    return
  end

  number = number or 0

  if neg then
    number = -number
  end
  --- @type parser.object.number
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

local function isKeyWord(word, tokenNext)
  if KeyWord[word] then
    return true
  end
  if word == 'goto' then
    if State.version == 'Lua 5.1' then
      return false
    end
    if State.version == 'LuaJIT' then
      if not tokenNext then
        return false
      end
      if CharMapWord[string.sub(tokenNext, 1, 1)] then
        return true
      end
      return false
    end
    return true
  end
  return false
end

--- @return parser.object.name?
local function parseName(asAction)
  local word = peekWord()
  if not word then
    return
  end
  if ChunkFinishMap[word] then
    return
  end
  if asAction and ChunkStartMap[word] then
    return
  end
  if not State.options.unicodeName and word:find('[\x80-\xff]') then
    Error.token('UNICODE_NAME')
  end
  if isKeyWord(word, Token.get()) then
    Error.token('KEYWORD')
  end
  local _, startPos, finishPos = Token.getWithPos()
  Token.next()
  return {
    type = 'name',
    start = startPos,
    finish = finishPos,
    [1] = word,
  }
end

--- @param parent parser.object.for
--- @return parser.object.forlist|parser.object.name?
local function parseNameOrList(parent)
  local first = parseName()
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
    local name = parseName(true)
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

local parseExp

--- @param mini? boolean
--- @return parser.object.explist?
local function parseExpList(mini)
  --- @type parser.object.explist?
  local list
  local wantSep = false
  while true do
    skipSpace()
    local token = Token.get()
    if not token then
      break
    end
    if ListFinishMap[token] then
      break
    end
    local _, start, finish = Token.getWithPos()
    if token == ',' then
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
      local exp = parseExp()
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

local function parseIndex()
  local start = getPosition(Token.getPos(), 'left')
  Token.next()
  skipSpace()
  local exp = parseExp()
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
  if Token.get() == ']' then
    index.finish = getPosition(Token.getPos(), 'right')
    Token.next()
  else
    Error.missSymbol(']')
  end
  return index
end

local function parseTable()
  local tbl = {
    type = 'table',
    start = getPosition(Token.getPos(), 'left'),
    finish = getPosition(Token.getPos(), 'right'),
  }
  Token.next()
  local index = 0
  local tindex = 0
  local wantSep = false
  while true do
    if
      (function()
        skipSpace(true)
        local token = Token.get()
        if token == '}' then
          Token.next()
          return true
        end
        if CharMapTSep[token] then
          if not wantSep then
            Error.missExp()
          end
          wantSep = false
          Token.next()
          return
        end
        local lastRight = lastRightPosition()

        if peekWord() then
          local savePoint = getSavePoint()
          local name = parseName()
          if name then
            skipSpace()
            if Token.get() == '=' then
              Token.next()
              if wantSep then
                pushError({
                  type = 'MISS_SEP_IN_TABLE',
                  start = lastRight,
                  finish = getPosition(Token.getPos(), 'left'),
                })
              end
              wantSep = true
              skipSpace()
              local fvalue = parseExp()
              local tfield = {
                type = 'tablefield',
                start = name.start,
                finish = name.finish,
                range = fvalue and fvalue.finish,
                node = tbl,
                parent = tbl,
                field = name,
                value = fvalue,
              }
              name.type = 'field'
              name.parent = tfield
              if fvalue then
                fvalue.parent = tfield
              else
                Error.missExp()
              end
              index = index + 1
              tbl[index] = tfield
              return
            end
          end
          savePoint()
        end

        local exp = parseExp(true)
        if exp then
          if wantSep then
            pushError({
              type = 'MISS_SEP_IN_TABLE',
              start = lastRight,
              finish = exp.start,
            })
          end
          wantSep = true
          if exp.type == 'varargs' then
            index = index + 1
            tbl[index] = exp
            exp.parent = tbl
            return
          end
          index = index + 1
          tindex = tindex + 1
          local texp = {
            type = 'tableexp',
            start = exp.start,
            finish = exp.finish,
            tindex = tindex,
            parent = tbl,
            value = exp,
          }
          exp.parent = texp
          tbl[index] = texp
          return
        end

        if token == '[' then
          if wantSep then
            pushError({
              type = 'MISS_SEP_IN_TABLE',
              start = lastRight,
              finish = getPosition(Token.getPos(), 'left'),
            })
          end
          wantSep = true
          local tindex0 = parseIndex()
          skipSpace()
          tindex0.type = 'tableindex'
          tindex0.node = tbl
          tindex0.parent = tbl
          index = index + 1
          tbl[index] = tindex0
          if expectAssign() then
            skipSpace()
            local ivalue = parseExp()
            if ivalue then
              ivalue.parent = tindex0
              tindex0.range = ivalue.finish
              tindex0.value = ivalue
            else
              Error.missExp()
            end
          else
            Error.missSymbol('=')
          end
          return
        end

        Error.missSymbol('}')
        return true
      end)()
    then
      break
    end
  end
  tbl.finish = lastRightPosition()
  return tbl
end

local function addDummySelf(node, call)
  if not node then
    return
  end
  if node.type ~= 'getmethod' then
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
  local self = {
    type = 'self',
    start = node.colon.start,
    finish = node.colon.finish,
    parent = call.args,
    [1] = 'self',
  }
  table.insert(call.args, 1, self)
end

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
  pushError({
    type = 'AMBIGUOUS_SYNTAX',
    start = parenPos,
    finish = call.finish,
  })
end

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

local function parseSimple(node, funcName)
  local currentName
  if node.type == 'getglobal' or node.type == 'getlocal' then
    currentName = node[1]
  end
  local lastMethod
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
      local dot = {
        type = token,
        start = getPosition(Token.getPos(), 'left'),
        finish = getPosition(Token.getPos(), 'right'),
      }
      Token.next()
      skipSpace()
      local field = parseName(true)
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
        pushError({
          type = 'MISS_FIELD',
          start = lastRightPosition(),
          finish = lastRightPosition(),
        })
      end
      node.parent = getfield
      node.next = getfield
      node = getfield
    elseif token == ':' then
      local colon = {
        type = token,
        start = getPosition(Token.getPos(), 'left'),
        finish = getPosition(Token.getPos(), 'right'),
      }
      Token.next()
      skipSpace()
      local method = parseName(true)
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
        pushError({
          type = 'MISS_METHOD',
          start = lastRightPosition(),
          finish = lastRightPosition(),
        })
      end
      node.parent = getmethod
      node.next = getmethod
      node = getmethod
      if lastMethod then
        Error.missSymbol('(', node.node.finish, node.node.finish)
      end
      lastMethod = getmethod
    elseif token == '(' then
      if funcName then
        break
      end
      local startPos = getPosition(Token.getPos(), 'left')
      local call = {
        type = 'call',
        start = node.start,
        node = node,
      }
      Token.next()
      local args = parseExpList()
      if Token.get() == ')' then
        call.finish = getPosition(Token.getPos(), 'right')
        Token.next()
      else
        call.finish = lastRightPosition()
        Error.missSymbol(')')
      end
      if args then
        args.type = 'callargs'
        args.start = startPos
        args.finish = call.finish
        args.parent = call
        call.args = args
      end
      addDummySelf(node, call)
      checkAmbiguityCall(call, startPos)
      node.parent = call
      node = call
    elseif token == '{' then
      if funcName then
        break
      end
      local tbl = parseTable()
      local call = {
        type = 'call',
        start = node.start,
        finish = tbl.finish,
        node = node,
      }
      local args = {
        type = 'callargs',
        start = tbl.start,
        finish = tbl.finish,
        parent = call,
        [1] = tbl,
      }
      call.args = args
      addDummySelf(node, call)
      tbl.parent = args
      node.parent = call
      node = call
    elseif CharMapStrSH[token] then
      if funcName then
        break
      end
      local str = parseShortString()
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
      node = call
    elseif CharMapStrLH[token] then
      local str = parseLongString()
      if str then
        if funcName then
          break
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
        node = call
      else
        local index = parseIndex()
        local bstart = index.start
        index.type = 'getindex'
        index.start = node.start
        index.node = node
        node.next = index
        node.parent = index
        node = index
        if funcName then
          pushError({
            type = 'INDEX_IN_FUNC_NAME',
            start = index.start,
            finish = index.finish,
          })
        end
      end
    else
      break
    end
  end
  if node.type == 'call' and node.node == lastMethod then
    lastMethod = nil
  end
  if node.type == 'call' then
    if node.node.special == 'error' or node.node.special == 'os.exit' then
      node.hasExit = true
    end
  end
  if node == lastMethod then
    if funcName then
      lastMethod = nil
    end
  end
  if lastMethod then
    Error.missSymbol('(', lastMethod.finish)
  end
  return node
end

--- local function a(...)
---   return function ()
---     return ... -- <--- ERROR: cannot use ... outside a vararg functions
---   end
--- end
--- @param varargs parser.object.varargs
local function checkVarargs(varargs)
  for i = #Chunk, 1, -1 do
    local chunk = Chunk[i]
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

--- @return parser.object.varargs
local function parseVarargs()
  local _, start, finish = assert(Token.getWithPos())
  --- @type parser.object.varargs
  local varargs = {
    type = 'varargs',
    start = start,
    finish = finish,
  }

  checkVarargs(varargs)
  Token.next()
  return varargs
end

--- @return parser.object.paren
local function parseParen()
  local _, start, finish = assert(Token.getWithPos())

  --- @type parser.object.paren
  local paren = {
    type = 'paren',
    start = start,
    finish = finish,
  }

  Token.next()

  skipSpace()

  local exp = parseExp()
  if exp then
    paren.exp = exp
    paren.finish = exp.finish
    exp.parent = paren
  else
    Error.missExp()
  end

  skipSpace()

  if Token.get() == ')' then
    paren.finish = getPosition(Token.getPos(), 'right')
    Token.next()
  else
    Error.missSymbol(')')
  end

  return paren
end

--- @param name string
--- @param pos integer
--- @return parser.object.local?
local function getLocal(name, pos)
  for i = #Chunk, 1, -1 do
    local res
    for _, loc in ipairs(Chunk[i].locals or {}) do
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

local parseAction

local function parseActions()
  local rtn, last
  while true do
    skipSpace(true)
    local token = Token.get()
    if token == ';' then
      Token.next()
    else
      if ChunkFinishMap[token] and isChunkFinishToken(token) then
        break
      end
      local action, failed = parseAction()
      if failed then
        if not skipUnknownSymbol() then
          break
        end
      end
      if action then
        if not rtn and action.type == 'return' then
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

local function parseParams(params, isLambda)
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
      if not params then
        params = {}
      end
      local _, start, finish = Token.getWithPos()
      local vararg = {
        type = '...',
        start = start,
        finish = finish,
        parent = params,
        [1] = '...',
      }
      local chunk = Chunk.get()
      chunk.vararg = vararg
      params[#params + 1] = vararg
      if hasDots then
        Error.token('ARGS_AFTER_DOTS')
      end
      hasDots = true
      Token.next()
    elseif CharMapWord[string.sub(token, 1, 1)] then
      if lastSep == false then
        Error.missSymbol(',')
      end
      lastSep = false
      if not params then
        params = {}
      end
      local _, start, finish = assert(Token.getWithPos())
      params[#params + 1] = createLocal({
        start = start,
        finish = finish,
        parent = params,
        [1] = token,
      })
      if hasDots then
        pushError({ type = 'ARGS_AFTER_DOTS', start = start, finish = finish })
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

local function parseFunction(isLocal, isAction)
  local _, funcLeft, funcRight = assert(Token.getWithPos())
  local func = {
    type = 'function',
    start = funcLeft,
    finish = funcRight,
    bstart = funcRight,
    keyword = {
      [1] = funcLeft,
      [2] = funcRight,
    },
  }
  Token.next()
  skipSpace(true)
  local hasLeftParen = Token.get() == '('
  if not hasLeftParen then
    local name = parseName()
    if name then
      local simple = parseSimple(name, true)
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
      hasLeftParen = Token.get() == '('
    end
  end
  local LastLocalCount = LocalCount
  LocalCount = 0
  Chunk.push(func)
  local params
  if func.name and func.name.type == 'getmethod' then
    if func.name.type == 'getmethod' then
      params = {
        type = 'funcargs',
        start = funcRight,
        finish = funcRight,
        parent = func,
      }
      params[1] = createLocal({
        start = funcRight,
        finish = funcRight,
        parent = params,
        [1] = 'self',
      })
      params[1].type = 'self'
    end
  end
  if hasLeftParen then
    params = params or {}
    local parenLeft = getPosition(Token.getPos(), 'left')
    Token.next()
    params = parseParams(params)
    params.type = 'funcargs'
    params.start = parenLeft
    params.finish = lastRightPosition()
    params.parent = func
    func.args = params
    skipSpace(true)
    if Token.get() == ')' then
      local parenRight = getPosition(Token.getPos(), 'right')
      func.finish = parenRight
      func.bstart = parenRight
      if params then
        params.finish = parenRight
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
  parseActions()
  Chunk.pop()
  if Token.get() == 'end' then
    local _, endLeft, endRight = Token.getWithPos()
    func.keyword[3] = endLeft
    func.keyword[4] = endRight
    func.finish = endRight
    Token.next()
  else
    func.finish = lastRightPosition()
    Error.missEnd(funcLeft, funcRight)
  end
  LocalCount = LastLocalCount
  return func
end

local function parseLambda(isDoublePipe)
  local lambdaLeft = getPosition(Token.getPos(), 'left')
  local lambdaRight = getPosition(Token.getPos(), 'right')
  local lambda = {
    type = 'function',
    start = lambdaLeft,
    finish = lambdaRight,
    bstart = lambdaRight,
    keyword = {
      [1] = lambdaLeft,
      [2] = lambdaRight,
    },
    hasReturn = true,
  }
  Token.next()
  local pipeLeft = getPosition(Token.getPos(), 'left')
  local pipeRight = getPosition(Token.getPos(), 'right')
  skipSpace(true)
  local params
  local LastLocalCount = LocalCount
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
    Chunk.push(lambda)
    LocalCount = 0
    params = parseParams({}, true)
    params.type = 'funcargs'
    params.start = pipeLeft
    params.finish = lastRightPosition()
    params.parent = lambda
    lambda.args = params
    skipSpace()
    if Token.get() == '|' then
      pipeRight = getPosition(Token.getPos(), 'right')
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
  local child = parseExp()

  -- don't want popChunk logic here as this is not a real chunk
  Chunk[#Chunk] = nil

  if child then
    -- create dummy return
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
  LocalCount = LastLocalCount
  return lambda
end

local function checkNeedParen(source)
  local token = Token.get()
  if token ~= '.' and token ~= ':' then
    return source
  end
  local exp = parseSimple(source, false)
  if exp == source then
    return exp
  end
  pushError({
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

--- @return parser.object.expr?
local function parseExpUnit()
  local token = Token.get()
  if token == '(' then
    return parseSimple(parseParen(), false)
  elseif token == '...' then
    return parseVarargs()
  elseif token == '{' then
    local table = parseTable()
    if not table then
      return
    end
    return checkNeedParen(table)
  elseif CharMapStrSH[token] then
    local string = parseShortString()
    if not string then
      return
    end
    return checkNeedParen(string)
  elseif CharMapStrLH[token] then
    local string = parseLongString()
    if not string then
      return
    end
    return checkNeedParen(string)
  end

  local number = parseNumber()
  if number then
    return number
  end

  if ChunkFinishMap[token] then
    return
  end

  if token == 'nil' then
    return parseNil()
  end

  if token == 'true' or token == 'false' then
    return parseBoolean()
  end

  if token == 'function' then
    return parseFunction()
  end

  -- FIXME: Use something other than nonstandardSymbol to check for lambda support
  if State.options.nonstandardSymbol['|lambda|'] and (token == '|' or token == '||') then
    return parseLambda(token == '||')
  end

  local node = parseName()
  if node then
    local nameNode = resolveName(node)
    if nameNode then
      return parseSimple(nameNode, false)
    end
  end
end

local function parseUnaryOP()
  local token = Token.get()
  local symbol = UnarySymbol[token] and token or UnaryAlias[token]
  if not symbol then
    return
  end
  local _, start, finish = Token.getWithPos()
  local myLevel = UnarySymbol[symbol]
  local op = {
    type = symbol,
    start = start,
    finish = finish,
  }
  Token.next()
  return op, myLevel
end

--- @param level integer # op level must greater than this level
--- @return parser.binop?, integer?
local function parseBinaryOP(asAction, level)
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

  local _, start, finish = assert(Token.getWithPos())

  --- @type parser.binop
  local op = {
    type = symbol,
    start = start,
    finish = finish,
  }

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

  if token == '//' or token == '<<' or token == '>>' then
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

--- @return parser.object.expr?
function parseExp(asAction, level)
  local exp --- @type parser.object.expr
  local uop, uopLevel = parseUnaryOP()
  if uop then
    skipSpace()
    local child = parseExp(asAction, uopLevel)
    -- Precompute negative numbers
    if uop.type == '-' and child and (child.type == 'number' or child.type == 'integer') then
      child.start = uop.start
      child[1] = -child[1]
      exp = child
    else
      --- @type parser.object.unary
      exp = {
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
    end
  else
    local e = parseExpUnit()
    if not e then
      return
    end
    exp = e
  end

  while true do
    skipSpace()
    local bop, bopLevel = parseBinaryOP(asAction, level)
    if not bop then
      break
    end

    local child --- @type parser.object.expr
    while true do
      skipSpace()
      local isForward = SymbolForward[bopLevel]
      child = parseExp(asAction, isForward and (bopLevel + 0.5) or bopLevel)
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

local function skipSeps()
  while true do
    skipSpace()
    if Token.get() == ',' then
      Error.missExp()
      Token.next()
    else
      break
    end
  end
end

--- @return parser.object?   first
--- @return parser.object?   second
--- @return parser.object[]? rest
local function parseSetValues()
  skipSpace()
  local first = parseExp()
  if not first then
    return nil
  end
  skipSpace()
  if Token.get() ~= ',' then
    return first
  end
  Token.next()
  skipSeps()
  local second = parseExp()
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
  local third = parseExp()
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
    local exp = parseExp()
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
    return nil
  end
  Token.next()
  skipSpace()
  local second = parser(true)
  if not second then
    Error.missName()
    return nil
  end
  if isLocal then
    createLocal(second, parseLocalAttrs())
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
    createLocal(third, parseLocalAttrs())
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
      createLocal(name, parseLocalAttrs())
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
        pushError({ type = 'SET_CONST', at = n })
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

local function compileExpAsAction(exp)
  Chunk.pushIntoCurrent(exp)
  if GetToSetMap[exp.type] then
    skipSpace()
    local isLocal
    if exp.type == 'getlocal' and exp[1] == State.ENVMode then
      exp.special = nil
      -- TODO: need + 1 at the end
      LocalCount = LocalCount - 1
      local loc = createLocal(exp, parseLocalAttrs())
      loc.locPos = exp.start
      loc.effect = math.maxinteger
      isLocal = true
      skipSpace()
    end
    local action, isSet = parseMultiVars(exp, parseExp, isLocal)
    if isSet or action.type == 'getmethod' then
      return action
    end
  end

  if exp.type == 'call' then
    if exp.hasExit then
      for i = #Chunk, 1, -1 do
        local block = Chunk[i]
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
        pushError({
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

  pushError({ type = 'EXP_IN_ACTION', at = exp })

  return exp
end

local function parseLocal()
  local locPos = getPosition(Token.getPos(), 'left')
  Token.next()
  skipSpace()
  local word = peekWord()
  if not word then
    Error.missName()
    return nil
  end

  if word == 'function' then
    local func = parseFunction(true, true)
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
    else
      Error.missName(func.keyword[2])
      Chunk.pushIntoCurrent(func)
      return func
    end
  end

  local name = parseName(true)
  if not name then
    Error.missName()
    return
  end
  local loc = createLocal(name, parseLocalAttrs())
  loc.locPos = locPos
  loc.effect = math.maxinteger
  Chunk.pushIntoCurrent(loc)
  skipSpace()
  parseMultiVars(loc, parseName, true)

  return loc
end

--- @return parser.object.do
local function parseDo()
  local _, left, right = assert(Token.getWithPos())
  --- @type parser.object.do
  local obj = {
    type = 'do',
    start = left,
    finish = right,
    bstart = right,
    keyword = {
      [1] = left,
      [2] = right,
    },
  }
  Token.next()
  Chunk.pushIntoCurrent(obj)
  Chunk.push(obj)
  parseActions()
  Chunk.pop()
  if Token.get() == 'end' then
    local _, start, finish = assert(Token.getWithPos())
    obj.finish = finish
    obj.keyword[3] = start
    obj.keyword[4] = finish
    Token.next()
  else
    Error.missEnd(left, right)
  end

  LocalCount = LocalCount - #(obj.locals or {})

  return obj
end

local function parseReturn()
  local _, returnLeft, returnRight = assert(Token.getWithPos())
  Token.next()
  skipSpace()
  local rtn = parseExpList(true)
  if rtn then
    rtn.type = 'return'
    rtn.start = returnLeft
  else
    rtn = {
      type = 'return',
      start = returnLeft,
      finish = returnRight,
    }
  end
  Chunk.pushIntoCurrent(rtn)
  for i = #Chunk, 1, -1 do
    local block = Chunk[i]
    if block.type == 'function' or block.type == 'main' then
      if not block.returns then
        block.returns = {}
      end
      block.returns[#block.returns + 1] = rtn
      break
    end
  end
  for i = #Chunk, 1, -1 do
    local block = Chunk[i]
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
local function parseLabel()
  local left = getPosition(Token.getPos(), 'left')
  Token.next()
  skipSpace()
  local name = parseName()
  skipSpace()

  if not name then
    Error.missName()
  end

  if Token.get() == '::' then
    Token.next()
  elseif name then
    Error.missSymbol('::')
  end

  if not name then
    return
  end

  label = name --[[@as parser.object.label]]
  label.type = 'label'

  Chunk.pushIntoCurrent(label)

  local block = guide.getBlock(label)
  if block then
    block.labels = block.labels or {}
    local name = label[1]
    local olabel = guide.getLabel(block, name)
    if olabel then
      if State.version == 'Lua 5.4' or block == guide.getBlock(olabel) then
        pushError({
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
    block.labels[name] = label
  end

  if State.version == 'Lua 5.1' then
    pushError({
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

local function parseGoTo()
  local start = getPosition(Token.getPos(), 'left')
  Token.next()
  skipSpace()

  local action = parseName()
  if not action then
    Error.missName()
    return nil
  end

  action.type = 'goto'
  action.keyStart = start

  for i = #Chunk, 1, -1 do
    local chunk = Chunk[i]
    if chunk.type == 'function' or chunk.type == 'main' then
      if not chunk.gotos then
        chunk.gotos = {}
      end
      chunk.gotos[#chunk.gotos + 1] = action
      break
    end
  end
  for i = #Chunk, 1, -1 do
    local chunk = Chunk[i]
    if chunk.type == 'ifblock' or chunk.type == 'elseifblock' or chunk.type == 'elseblock' then
      chunk.hasGoTo = true
      break
    end
  end

  Chunk.pushIntoCurrent(action)
  return action
end

--- @param parent parser.object.if
--- @return parser.object.ifblock
local function parseIfBlock(parent)
  local _, ifLeft, ifRight = assert(Token.getWithPos())
  Token.next()
  --- @type parser.object.ifblock
  local obj = {
    type = 'ifblock',
    parent = parent,
    start = ifLeft,
    finish = ifRight,
    bstart = ifRight,
    keyword = {
      [1] = ifLeft,
      [2] = ifRight,
    },
  }
  skipSpace()
  local filter = parseExp()
  if filter then
    obj.filter = filter
    obj.finish = filter.finish
    obj.bstart = obj.finish
    filter.parent = obj
  else
    Error.missExp()
  end
  skipSpace()
  local thenToken, thenStart, thenFinish = Token.getWithPos()
  if thenToken == 'then' or thenToken == 'do' then
    obj.finish = assert(thenFinish)
    obj.bstart = obj.finish
    obj.keyword[3] = assert(thenStart)
    obj.keyword[4] = obj.finish
    if thenToken == 'do' then
      Error.token('ERR_THEN_AS_DO', {
        fix = { title = 'FIX_THEN_AS_DO', { text = 'then' } },
      })
    end
    Token.next()
  else
    Error.missSymbol('then')
  end
  Chunk.push(obj)
  parseActions()
  Chunk.pop()
  obj.finish = getPosition(Token.getPos(), 'left')
  if obj.locals then
    LocalCount = LocalCount - #obj.locals
  end
  return obj
end

local function parseElseIfBlock(parent)
  local _, ifLeft, ifRight = assert(Token.getWithPos())
  local elseifblock = {
    type = 'elseifblock',
    parent = parent,
    start = ifLeft,
    finish = ifRight,
    bstart = ifRight,
    keyword = {
      [1] = ifLeft,
      [2] = ifRight,
    },
  }
  Token.next()
  skipSpace()
  local filter = parseExp()
  if filter then
    elseifblock.filter = filter
    elseifblock.finish = filter.finish
    elseifblock.bstart = elseifblock.finish
    filter.parent = elseifblock
  else
    Error.missExp()
  end
  skipSpace()
  local thenToken, thenLeft, thenRight = Token.getWithPos()
  if thenToken == 'then' or thenToken == 'do' then
    elseifblock.finish = thenRight
    elseifblock.bstart = elseifblock.finish
    elseifblock.keyword[3] = thenLeft
    elseifblock.keyword[4] = elseifblock.finish
    if thenToken == 'do' then
      Error.token('ERR_THEN_AS_DO', {
        fix = { title = 'FIX_THEN_AS_DO', { text = 'then' } },
      })
    end
    Token.next()
  else
    Error.missSymbol('then')
  end
  Chunk.push(elseifblock)
  parseActions()
  Chunk.pop()
  elseifblock.finish = getPosition(Token.getPos(), 'left')
  if elseifblock.locals then
    LocalCount = LocalCount - #elseifblock.locals
  end
  return elseifblock
end

local function parseElseBlock(parent)
  local _, ifLeft, ifRight = assert(Token.getWithPos())
  local elseblock = {
    type = 'elseblock',
    parent = parent,
    start = ifLeft,
    finish = ifRight,
    bstart = ifRight,
    keyword = {
      [1] = ifLeft,
      [2] = ifRight,
    },
  }
  Token.next()
  skipSpace()
  Chunk.push(elseblock)
  parseActions()
  Chunk.pop()
  elseblock.finish = getPosition(Token.getPos(), 'left')
  if elseblock.locals then
    LocalCount = LocalCount - #elseblock.locals
  end
  return elseblock
end

local function parseIf()
  local token, left, right = Token.getWithPos()
  local obj = {
    type = 'if',
    start = left,
    finish = right,
  }
  Chunk.pushIntoCurrent(obj)
  if token ~= 'if' then
    Error.missSymbol('if', left, left)
  end
  local hasElse
  while true do
    local word = Token.get()
    local child
    if word == 'if' then
      child = parseIfBlock(obj)
    elseif word == 'elseif' then
      child = parseElseIfBlock(obj)
    elseif word == 'else' then
      child = parseElseBlock(obj)
    end
    if not child then
      break
    end
    if hasElse then
      pushError({ type = 'BLOCK_AFTER_ELSE', at = child })
    end
    if word == 'else' then
      hasElse = true
    end
    obj[#obj + 1] = child
    obj.finish = child.finish
    skipSpace()
  end

  if Token.get() == 'end' then
    obj.finish = getPosition(Token.getPos() + 2, 'right')
    Token.next()
  else
    Error.missEnd(obj[1].keyword[1], obj[1].keyword[2])
  end

  return obj
end

--- @return parser.object.for|parser.object.loop|parser.object.in
local function parseFor()
  local _, start, finish = assert(Token.getWithPos())
  --- @type parser.object.for
  local action = {
    type = 'for',
    start = start,
    finish = finish,
    keyword = { start, finish },
    bstart = finish,
  }

  Token.next()
  Chunk.pushIntoCurrent(action)
  Chunk.push(action)
  skipSpace()
  local nameOrList = parseNameOrList(action)
  if not nameOrList then
    Error.missName()
  end
  skipSpace()
  local forStateVars
  -- for i =
  if expectAssign() then
    local loop = action --[[@as parser.object.loop]]
    loop.type = 'loop'

    skipSpace()
    local expList = parseExpList()
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
    forStateVars = 3
    LocalCount = LocalCount + forStateVars
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
        pushError({
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
      pushError({
        type = 'MISS_LOOP_MIN',
        start = lastRightPosition(),
        finish = lastRightPosition(),
      })
    end

    if loop.loc then
      loop.loc.effect = loop.finish
    end
  elseif Token.get() == 'in' then
    local forin = action --[[@as parser.object.in]]
    forin.type = 'in'
    local _, inLeft, inRight = assert(Token.getWithPos())
    Token.next()
    skipSpace()

    local exps = parseExpList()

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

    if State.version == 'Lua 5.4' then
      forStateVars = 4
    else
      forStateVars = 3
    end
    LocalCount = LocalCount + forStateVars

    if list then
      local lastName = list[#list]
      list.range = lastName and lastName.range or inRight
      forin.keys = list
      for _, obj in ipairs(list) do
        local loc = createLocal(obj)
        loc.parent = forin
        loc.effect = forin.finish
      end
    end
  else
    Error.missSymbol('in')
  end

  skipSpace()
  local doToken = Token.get()
  if doToken == 'do' or doToken == 'then' then
    local _, left, right = assert(Token.getWithPos())
    action.finish = left
    action.bstart = action.finish
    action.keyword[#action.keyword + 1] = left
    action.keyword[#action.keyword + 1] = right
    if doToken == 'then' then
      Error.token('ERR_DO_AS_THEN', {
        fix = { title = 'FIX_DO_AS_THEN', { text = 'do' } },
      })
    end
    Token.next()
  else
    Error.missSymbol('do')
  end

  skipSpace()
  parseActions()
  Chunk.pop()

  skipSpace()
  if Token.get() == 'end' then
    local _, left, right = assert(Token.getWithPos())
    action.finish = right
    action.keyword[#action.keyword + 1] = left
    action.keyword[#action.keyword + 1] = action.finish
    Token.next()
  else
    Error.missEnd(action.keyword[1], action.keyword[2])
  end

  LocalCount = LocalCount - #(action.locals or {})
  LocalCount = LocalCount - (forStateVars or 0)

  return action
end

--- @return parser.object.while
local function parseWhile()
  local _, start, finish = assert(Token.getWithPos())
  --- @type parser.object.while
  local action = {
    type = 'while',
    start = start,
    finish = finish,
    keyword = { start, finish },
    bstart = finish,
  }
  Token.next()

  skipSpace()
  local tokenNext = Token.get()
  local filter = tokenNext ~= 'do' and tokenNext ~= 'then' and parseExp()
  if filter then
    action.filter = filter
    action.finish = filter.finish
    filter.parent = action
  else
    Error.missExp()
  end

  skipSpace()
  local doToken = Token.get()
  if doToken == 'do' or doToken == 'then' then
    local _, left, right = assert(Token.getWithPos())
    action.finish = left
    action.bstart = left
    action.keyword[#action.keyword + 1] = left
    action.keyword[#action.keyword + 1] = right
    if doToken == 'then' then
      Error.token('ERR_DO_AS_THEN', {
        fix = { title = 'FIX_DO_AS_THEN', { text = 'do' } },
      })
    end
    Token.next()
  else
    Error.missSymbol('do')
  end

  Chunk.pushIntoCurrent(action)
  Chunk.push(action)
  skipSpace()
  parseActions()
  Chunk.pop()

  skipSpace()
  if Token.get() == 'end' then
    local _, left, right = assert(Token.getWithPos())
    action.finish = right
    action.keyword[#action.keyword + 1] = left
    action.keyword[#action.keyword + 1] = action.finish
    Token.next()
  else
    Error.missEnd(action.keyword[1], action.keyword[2])
  end

  LocalCount = LocalCount - #(action.locals or {})

  return action
end

local function parseRepeat()
  local _, start, finish = assert(Token.getWithPos())
  local action = {
    type = 'repeat',
    start = start,
    finish = finish,
    keyword = {},
  }
  action.bstart = action.finish
  action.keyword[1] = action.start
  action.keyword[2] = action.finish
  Token.next()

  Chunk.pushIntoCurrent(action)
  Chunk.push(action)
  skipSpace()
  parseActions()

  skipSpace()
  if Token.get() == 'until' then
    local _, start, finish = Token.getWithPos()
    action.finish = finish
    action.keyword[#action.keyword + 1] = start
    action.keyword[#action.keyword + 1] = finish
    Token.next()

    skipSpace()
    local filter = parseExp()
    if filter then
      action.filter = filter
      filter.parent = action
    else
      Error.missExp()
    end
  else
    Error.missSymbol('until')
  end

  Chunk.pop()
  if action.filter then
    action.finish = action.filter.finish
  end

  if action.locals then
    LocalCount = LocalCount - #action.locals
  end

  return action
end

local function parseBreak()
  local _, start, finish = Token.getWithPos()
  Token.next()
  skipSpace()
  local action = {
    type = 'break',
    start = start,
    finish = finish,
  }

  local ok
  for i = #Chunk, 1, -1 do
    local chunk = Chunk[i]
    if chunk.type == 'function' then
      break
    end
    if
      chunk.type == 'while'
      or chunk.type == 'in'
      or chunk.type == 'loop'
      or chunk.type == 'repeat'
      or chunk.type == 'for'
    then
      if not chunk.breaks then
        chunk.breaks = {}
      end
      chunk.breaks[#chunk.breaks + 1] = action
      ok = true
      break
    end
  end
  for i = #Chunk, 1, -1 do
    local chunk = Chunk[i]
    if chunk.type == 'ifblock' or chunk.type == 'elseifblock' or chunk.type == 'elseblock' then
      chunk.hasBreak = true
      break
    end
  end
  if not ok and Mode == 'Lua' then
    pushError({ type = 'BREAK_OUTSIDE', at = action })
  end

  Chunk.pushIntoCurrent(action)
  return action
end

--- @return parser.object.union? action
--- @return true? err
function parseAction()
  local token = Token.get()

  if token == '::' then
    return parseLabel()
  elseif token == 'local' then
    return parseLocal()
  elseif token == 'if' or token == 'elseif' or token == 'else' then
    return parseIf()
  elseif token == 'for' then
    return parseFor()
  elseif token == 'do' then
    return parseDo()
  elseif token == 'return' then
    return parseReturn()
  elseif token == 'break' then
    return parseBreak()
  elseif token == 'continue' and State.options.nonstandardSymbol['continue'] then
    return parseBreak()
  elseif token == 'while' then
    return parseWhile()
  elseif token == 'repeat' then
    return parseRepeat()
  elseif token == 'goto' and isKeyWord('goto', Token.getPrev()) then
    return parseGoTo()
  elseif token == 'function' then
    local exp = parseFunction(false, true)
    local name = exp.name
    if name then
      exp.name = nil
      name.type = GetToSetMap[name.type]
      name.value = exp
      name.vstart = exp.start
      name.range = exp.finish
      exp.parent = name
      if name.type == 'setlocal' then
        local loc = name.node
        if loc.attrs then
          pushError({ type = 'SET_CONST', at = name })
        end
      end
      Chunk.pushIntoCurrent(name)
      return name
    else
      Chunk.pushIntoCurrent(exp)
      Error.missName(exp.keyword[2])
      return exp
    end
  end

  local exp = parseExp(true)
  if exp then
    local action = compileExpAsAction(exp)
    if action then
      return action
    end
  end
  return nil, true
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

--- @return parser.object.main
local function parseLua()
  local main = {
    type = 'main',
    start = 0,
    finish = 0,
  }
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
  LocalCount = 0
  skipFirstComment()
  while true do
    parseActions()
    if Token.Index <= #Token.Tokens then
      unknownSymbol()
      Token.next()
    else
      break
    end
  end
  Chunk.pop()
  main.finish = getPosition(#Lua, 'right')

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
  LocalCount = 0
  LocalLimited = false
  Chunk.clear()
  Token.Tokens = tokens(lua)
  Token.Index = 1

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
  pushError = function(err)
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
end

--- @param lua string
--- @param mode 'Lua' | 'Nil' | 'Boolean' | 'String' | 'Number' | 'Name' | 'Exp' | 'Action'
--- @param version string
--- @param options table
return function(lua, mode, version, options)
  Mode = mode
  initState(lua, version, options)
  skipSpace()
  if mode == 'Lua' then
    State.ast = parseLua()
  elseif mode == 'Nil' then
    State.ast = parseNil()
  elseif mode == 'Boolean' then
    State.ast = parseBoolean()
  elseif mode == 'String' then
    State.ast = parseString()
  elseif mode == 'Number' then
    State.ast = parseNumber()
  elseif mode == 'Name' then
    State.ast = parseName()
  elseif mode == 'Exp' then
    State.ast = parseExp()
  elseif mode == 'Action' then
    State.ast = parseAction()
  end

  if State.ast then
    State.ast.state = State
  end

  while true do
    if Token.Index <= #Token.Tokens then
      unknownSymbol()
      Token.next()
    else
      break
    end
  end

  return State
end
