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

--- @alias parser.object.union
--- | parser.object.main
--- | parser.object.name
--- | parser.object.forlist
--- | parser.object.expr
--- | parser.object.block
--- | parser.object.local

--- @alias parser.object.expr
--- | parser.object.binop
--- | parser.object.unary
--- | parser.object.boolean
--- | parser.object.string
--- | parser.object.number
--- | parser.object.varargs
--- | parser.object.paren
--- | parser.object.label
--- | parser.object.explist

--- @alias parser.object.block
--- | parser.object.if
--- | parser.object.ifblock
--- | parser.object.for
--- | parser.object.loop
--- | parser.object.in
--- | parser.object.while

--- @class parser.object.base
--- @field start integer
--- @field finish integer
--- @field parent? parser.object.union
--- @field special? string
--- @field state? parser.state

--- @class parser.binop
--- @field type 'or' | 'and' | '<=' | '>=' | '<' | '>' | '~=' | '==' | '|' | '~' | '&' | '<<' | '>>' | '..' | '+' | '-' | '*' | '//' | '/' | '%' | '^'
--- @field start integer
--- @field finish integer

--- @class parser.object.name : parser.object.base
--- @field type 'name'
--- @field [1] string value

--- @class parser.object.forlist : parser.object.base
--- @field type 'list'
--- @field [integer] parser.object.name

--- @class parser.object.explist : parser.object.base
--- @field type 'list'
--- @field [integer] parser.object.expr

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
--- @field [1] string

--- @class parser.object.label : parser.object.base
--- @field type 'label'
--- @field [1] string value

--- @class parser.object.boolean : parser.object.base
--- @field type 'boolean'
--- @field [1] boolean value

--- @class parser.object.string : parser.object.base
--- @field type 'string'
--- @field escs? (string|integer)[] [int, int, string, int, int, string, ...]
--- @field [1] string value
--- @field [2] integer string delimiter

--- @class parser.object.number : parser.object.base
--- @field type 'number'|'integer'

--- @class parser.object.unary : parser.object.base
--- @field type 'unary'
--- @field [1] parser.object.expr?

--- @class parser.object.varargs : parser.object.base
--- @field type 'varargs'
--- @field node? unknown

--- @class parser.object.block.common : parser.object.base
--- @field parent? parser.object.expr
--- @field labels? table<string,parser.object.label>
--- @field locals parser.object.local[]
--- @field gotos
--- @field bstart integer Block start

--- @class parser.object.paren : parser.object.base
--- @field type 'paren'
--- @field exp? parser.object.expr

--- If blocks

--- @class parser.object.if : parser.object.block.common
--- @field type 'if'

--- @class parser.object.ifblock : parser.object.block.common
--- @field type 'ifblock'
--- @field parent parser.object.if
--- @field start integer
--- @field filter? parser.object? Condition of if block
--- @field keyword [integer,integer]

--- Loops

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

--- @class parser.object.binop : parser.object.base
--- @field type 'binary
--- @field op parser.binop
--- @field [1] parser.object.expr
--- @field [2] parser.object.expr


--- @class parser.state.err
--- @field type string
--- @field start? parser.position
--- @field finish? parser.position
--- @field info? table
--- @field fix? table
--- @field version? string[]|string
--- @field level? string | 'Error' | 'Warning'

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
local Index --- @type integer
local Mode
local Tokens --- @type (integer|string)[]
local Chunk, LastTokenFinish, LocalCount, LocalLimited

--- @return string?
local function get_token()
  return Tokens[Index + 1] --[[@as string]]
end

--- @return string?
local function next_token()
  Index = Index + 2
  return get_token()
end

--- @return integer
local function get_token_pos()
  return Tokens[Index] --[[@as integer]]
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

--- @param offset integer
--- @param leftOrRight '"left"'|'"right"'
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

--- @return string?  word
--- @return integer? startPosition
--- @return integer? finishPosition
local function peekWord()
  local token = get_token()
  if not token or not CharMapWord[token:sub(1, 1)] then
    return
  end
  local startPos = getPosition(get_token_pos(), 'left')
  local finishPos = getPosition(get_token_pos() + #token - 1, 'right')
  return token, startPos, finishPos
end

local function lastRightPosition()
  if Index < 2 then
    return 0
  end
  local token = Tokens[Index - 1]
  if NLMap[token] then
    return LastTokenFinish
  elseif token then
    return getPosition(Tokens[Index - 2] + #token - 1, 'right')
  else
    return getPosition(#Lua, 'right')
  end
end

local function missSymbol(symbol, start, finish)
  pushError({
    type = 'MISS_SYMBOL',
    start = start or lastRightPosition(),
    finish = finish or start or lastRightPosition(),
    info = {
      symbol = symbol,
    },
  })
end

local function missExp()
  pushError({
    type = 'MISS_EXP',
    start = lastRightPosition(),
    finish = lastRightPosition(),
  })
end

local function missName(pos)
  pushError({
    type = 'MISS_NAME',
    start = pos or lastRightPosition(),
    finish = pos or lastRightPosition(),
  })
end

local function missEnd(relatedStart, relatedFinish)
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

local function unknownSymbol(start, finish, word)
  local token = word or get_token()
  if not token then
    return false
  end
  pushError({
    type = 'UNKNOWN_SYMBOL',
    start = start or getPosition(get_token_pos(), 'left'),
    finish = finish or getPosition(get_token_pos() + #token - 1, 'right'),
    info = {
      symbol = token,
    },
  })
  return true
end

local function skipUnknownSymbol()
  if unknownSymbol() then
    next_token()
    return true
  end
  return false
end

local function skipNL()
  local token = get_token()
  if NLMap[token] then
    if Index >= 2 and not NLMap[Tokens[Index - 1]] then
      LastTokenFinish = getPosition(Tokens[Index - 2] + #Tokens[Index - 1] - 1, 'right')
    end
    Line = Line + 1
    LineOffset = get_token_pos() + #token
    next_token()
    State.lines[Line] = LineOffset
    return true
  end
  return false
end

local function getSavePoint()
  local index = Index
  local line = Line
  local lineOffset = LineOffset
  local errs = State.errs
  local errCount = #errs
  return function()
    Index = index
    Line = line
    LineOffset = lineOffset
    for i = errCount + 1, #errs do
      errs[i] = nil
    end
  end
end

local function fastForwardToken(offset)
  while true do
    local myOffset = get_token_pos()
    if not myOffset or myOffset >= offset then
      break
    end
    local token = get_token()
    if NLMap[token] then
      Line = Line + 1
      LineOffset = get_token_pos() + #token
      State.lines[Line] = LineOffset
    end
    next_token()
  end
end

local function resolveLongString(finishMark)
  skipNL()
  local miss
  local start = get_token_pos()
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
  local start, finish, mark = string.find(Lua, '^(%[%=*%[)', get_token_pos())
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

local function pushCommentHeadError(left)
  if State.options.nonstandardSymbol['//'] then
    return
  end
  pushError({
    type = 'ERR_COMMENT_PREFIX',
    start = left,
    finish = left + 2,
    fix = {
      title = 'FIX_COMMENT_PREFIX',
      {
        start = left,
        finish = left + 2,
        text = '--',
      },
    },
  })
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
  local token = get_token()
  if token == '--' or (token == '//' and (isAction or State.options.nonstandardSymbol['//'])) then
    local start = get_token_pos()
    local left = getPosition(start, 'left')
    local chead = false
    if token == '//' then
      chead = true
      pushCommentHeadError(left)
    end
    next_token()
    local longComment = start + 2 == get_token_pos() and parseLongString()
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
      local nl = get_token()
      if not nl or NLMap[nl] then
        break
      end
      next_token()
    end
    local right = get_token_pos() and (get_token_pos() - 1) or #Lua
    State.comms[#State.comms + 1] = {
      type = chead and 'comment.cshort' or 'comment.short',
      start = left,
      finish = getPosition(right, 'right'),
      text = Lua:sub(start + 2, right),
    }
    return true
  end
  if token == '/*' then
    local start = get_token_pos()
    local left = getPosition(start, 'left')
    next_token()
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
  local token = get_token()
  if token == '=' then
    next_token()
    return true
  end
  if token == '==' then
    local left = getPosition(get_token_pos(), 'left')
    local right = getPosition(get_token_pos() + #token - 1, 'right')
    pushError({
      type = 'ERR_ASSIGN_AS_EQ',
      start = left,
      finish = right,
      fix = {
        title = 'FIX_ASSIGN_AS_EQ',
        {
          start = left,
          finish = right,
          text = '=',
        },
      },
    })
    next_token()
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
      next_token()
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
    local token = get_token()
    if token ~= '<' then
      break
    end
    if not attrs then
      attrs = {
        type = 'localattrs',
      }
    end
    local attr = {
      type = 'localattr',
      parent = attrs,
      start = getPosition(get_token_pos(), 'left'),
      finish = getPosition(get_token_pos(), 'right'),
    }
    attrs[#attrs + 1] = attr
    local token = next_token()
    skipSpace()

    local word, wstart, wfinish = peekWord()
    if word then
      attr[1] = word
      attr.finish = wfinish
      next_token()
      if word ~= 'const' and word ~= 'close' then
        pushError({
          type = 'UNKNOWN_ATTRIBUTE',
          start = wstart,
          finish = wfinish,
        })
      end
    else
      missName()
    end
    attr.finish = lastRightPosition()
    skipSpace()

    token = get_token()

    if token == '>' then
      attr.finish = getPosition(get_token_pos(), 'right')
      next_token()
    elseif token == '>=' then
      attr.finish = getPosition(get_token_pos(), 'right')
      pushError({
        type = 'MISS_SPACE_BETWEEN',
        start = getPosition(get_token_pos(), 'left'),
        finish = getPosition(get_token_pos() + #token - 1, 'right'),
      })
      next_token()
    else
      missSymbol('>')
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

  -- Add local to current chunk
  local chunk = Chunk[#Chunk]
  if chunk then
    chunk.locals = chunk.locals or {}
    local locals = chunk.locals
    locals[#locals + 1] = obj1
    LocalCount = LocalCount + 1
    if not LocalLimited and LocalCount > LocalLimit then
      LocalLimited = true
      pushError({ type = 'LOCAL_LIMIT', at = obj1 })
    end
  end

  return obj1
end

local function pushChunk(chunk)
  Chunk[#Chunk + 1] = chunk
end

local function resolveLable(label, obj)
  if not label.ref then
    label.ref = {}
  end
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
  if not locals then
    return
  end

  for i = 1, #locals do
    if
      (function()
        local loc = locals[i]
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
    then
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

local function popChunk()
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

local function parseNil()
  if get_token() ~= 'nil' then
    return
  end
  local offset = get_token_pos()
  next_token()
  return {
    type = 'nil',
    start = getPosition(offset, 'left'),
    finish = getPosition(offset + 2, 'right'),
  }
end

--- @return parser.object.boolean?
local function parseBoolean()
  local word = get_token()
  if word ~= 'true' and word ~= 'false' then
    return
  end
  local start = getPosition(get_token_pos(), 'left')
  local finish = getPosition(get_token_pos() + #word - 1, 'right')
  next_token()
  return {
    type = 'boolean',
    start = start,
    finish = finish,
    [1] = word == 'true' and true or false,
  }
end

local function parseStringUnicode()
  local offset = get_token_pos() + 1
  if Lua:sub(offset, offset) ~= '{' then
    local pos = getPosition(offset, 'left')
    missSymbol('{', pos)
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
    missSymbol('}', rightPos)
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
  local mark = get_token()
  local startOffset = get_token_pos()
  local startPos = getPosition(startOffset, 'left')
  next_token()
  local stringIndex = 0
  local currentOffset = startOffset + 1
  local escs = {}
  while true do
    if
      (function()
        local token = get_token()
        if not token then
          stringIndex = stringIndex + 1
          stringPool[stringIndex] = Lua:sub(currentOffset or -1)
          missSymbol(mark)
          return true
        elseif token == mark then
          stringIndex = stringIndex + 1
          stringPool[stringIndex] = Lua:sub(currentOffset, get_token_pos() - 1)
          next_token()
          return true
        elseif NLMap[token] then
          stringIndex = stringIndex + 1
          stringPool[stringIndex] = Lua:sub(currentOffset, get_token_pos() - 1)
          missSymbol(mark)
          return true
        elseif token == '\\' then
          stringIndex = stringIndex + 1
          stringPool[stringIndex] = Lua:sub(currentOffset, get_token_pos() - 1)
          currentOffset = get_token_pos()
          next_token()
          if not get_token_pos() then
            return
          end
          local escLeft = getPosition(currentOffset, 'left')
          -- has space?
          if get_token_pos() - currentOffset > 1 then
            local right = getPosition(currentOffset + 1, 'right')
            pushError({
              type = 'ERR_ESC',
              start = escLeft,
              finish = right,
            })
            escs[#escs + 1] = escLeft
            escs[#escs + 1] = right
            escs[#escs + 1] = 'err'
            return
          end

          local nextToken = get_token():sub(1, 1)
          if EscMap[nextToken] then
            stringIndex = stringIndex + 1
            stringPool[stringIndex] = EscMap[nextToken]
            currentOffset = get_token_pos() + #nextToken
            next_token()
            escs[#escs + 1] = escLeft
            escs[#escs + 1] = escLeft + 2
            escs[#escs + 1] = 'normal'
            return
          elseif nextToken == mark then
            stringIndex = stringIndex + 1
            stringPool[stringIndex] = mark
            currentOffset = get_token_pos() + #nextToken
            next_token()
            escs[#escs + 1] = escLeft
            escs[#escs + 1] = escLeft + 2
            escs[#escs + 1] = 'normal'
            return
          elseif nextToken == 'z' then
            next_token()
            repeat
            until not skipNL()
            currentOffset = get_token_pos()
            escs[#escs + 1] = escLeft
            escs[#escs + 1] = escLeft + 2
            escs[#escs + 1] = 'normal'
            return
          elseif CharMapNumber[nextToken] then
            local numbers = get_token():match('^%d+')
            if #numbers > 3 then
              numbers = string.sub(numbers, 1, 3)
            end
            currentOffset = get_token_pos() + #numbers
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
          elseif nextToken == 'x' then
            local left = getPosition(get_token_pos() - 1, 'left')
            local x16 = get_token():sub(2, 3)
            local byte = tonumber(x16, 16)
            if byte then
              currentOffset = get_token_pos() + 3
              stringIndex = stringIndex + 1
              stringPool[stringIndex] = string.char(byte)
            else
              currentOffset = get_token_pos() + 1
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
            next_token()
            return
          elseif nextToken == 'u' then
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
          elseif NLMap[nextToken] then
            stringIndex = stringIndex + 1
            stringPool[stringIndex] = '\n'
            currentOffset = get_token_pos() + #nextToken
            skipNL()
            escs[#escs + 1] = escLeft
            escs[#escs + 1] = escLeft + 1
            escs[#escs + 1] = 'normal'
            return
          end
          local right = getPosition(currentOffset + 1, 'right')
          pushError({
            type = 'ERR_ESC',
            start = escLeft,
            finish = right,
          })
          escs[#escs + 1] = escLeft
          escs[#escs + 1] = right
          escs[#escs + 1] = 'err'
        end
        next_token()
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
        start = startPos,
        finish = str.finish,
        info = {
          symbol = '"',
        },
        fix = {
          title = 'FIX_NONSTANDARD_SYMBOL',
          symbol = '"',
          {
            start = startPos,
            finish = startPos + 1,
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
  local c = get_token()
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
  local echar = string.sub(Lua, offset, offset)
  if CharMapE10[echar] then
    integer = false
    offset = offset + 1
    local nextChar = string.sub(Lua, offset, offset)
    if CharMapSign[nextChar] then
      offset = offset + 1
    end
    local exp = string.match(Lua, '^%d*', offset)
    offset = offset + #exp
    if #exp == 0 then
      pushError({
        type = 'MISS_EXPONENT',
        start = getPosition(offset - 1, 'right'),
        finish = getPosition(offset - 1, 'right'),
      })
    end
  end
  return tonumber(string.sub(Lua, start, offset - 1)), offset, integer
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
      word = string.sub(word, offset)
    elseif string.upper(string.sub(word, 1, 3)) == 'ULL' then
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
  if string.upper(string.sub(word, 1, 1)) == 'I' then
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
    word = string.sub(word, offset)
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
  local offset = get_token_pos()
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

local function isKeyWord(word, nextToken)
  if KeyWord[word] then
    return true
  end
  if word == 'goto' then
    if State.version == 'Lua 5.1' then
      return false
    end
    if State.version == 'LuaJIT' then
      if not nextToken then
        return false
      end
      if CharMapWord[string.sub(nextToken, 1, 1)] then
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
  local startPos = getPosition(get_token_pos(), 'left')
  local finishPos = getPosition(get_token_pos() + #word - 1, 'right')
  next_token()
  if not State.options.unicodeName and word:find('[\x80-\xff]') then
    pushError({
      type = 'UNICODE_NAME',
      start = startPos,
      finish = finishPos,
    })
  end
  if isKeyWord(word, get_token()) then
    pushError({
      type = 'KEYWORD',
      start = startPos,
      finish = finishPos,
    })
  end
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
    if get_token() ~= ',' then
      break
    end
    next_token()
    skipSpace()
    local name = parseName(true)
    if not name then
      missName()
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
    local token = get_token()
    if not token then
      break
    end
    if ListFinishMap[token] then
      break
    end
    if token == ',' then
      local sepPos = getPosition(get_token_pos(), 'right')
      if not wantSep then
        pushError({
          type = 'UNEXPECT_SYMBOL',
          start = getPosition(get_token_pos(), 'left'),
          finish = sepPos,
          info = {
            symbol = ',',
          },
        })
      end
      wantSep = false
      next_token()
    else
      if mini then
        if wantSep then
          break
        end
        local nextToken = peekWord()
        if
          isKeyWord(nextToken, Tokens[Index + 2])
          and nextToken ~= 'function'
          and nextToken ~= 'true'
          and nextToken ~= 'false'
          and nextToken ~= 'nil'
          and nextToken ~= 'not'
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
        missSymbol(',', list[#list].finish, exp.start)
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
    missExp()
  end
  return list
end

local function parseIndex()
  local start = getPosition(get_token_pos(), 'left')
  next_token()
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
    missExp()
  end
  skipSpace()
  if get_token() == ']' then
    index.finish = getPosition(get_token_pos(), 'right')
    next_token()
  else
    missSymbol(']')
  end
  return index
end

local function parseTable()
  local tbl = {
    type = 'table',
    start = getPosition(get_token_pos(), 'left'),
    finish = getPosition(get_token_pos(), 'right'),
  }
  next_token()
  local index = 0
  local tindex = 0
  local wantSep = false
  while true do
    if
      (function()
        skipSpace(true)
        local token = get_token()
        if token == '}' then
          next_token()
          return true
        end
        if CharMapTSep[token] then
          if not wantSep then
            missExp()
          end
          wantSep = false
          next_token()
          return
        end
        local lastRight = lastRightPosition()

        if peekWord() then
          local savePoint = getSavePoint()
          local name = parseName()
          if name then
            skipSpace()
            if get_token() == '=' then
              next_token()
              if wantSep then
                pushError({
                  type = 'MISS_SEP_IN_TABLE',
                  start = lastRight,
                  finish = getPosition(get_token_pos(), 'left'),
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
                missExp()
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
              finish = getPosition(get_token_pos(), 'left'),
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
              missExp()
            end
          else
            missSymbol('=')
          end
          return
        end

        missSymbol('}')
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
        missSymbol('(', node.node.finish, node.node.finish)
      end
      lastMethod = nil
    end
    skipSpace()
    local token = get_token()
    if token == '.' then
      local dot = {
        type = token,
        start = getPosition(get_token_pos(), 'left'),
        finish = getPosition(get_token_pos(), 'right'),
      }
      next_token()
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
        start = getPosition(get_token_pos(), 'left'),
        finish = getPosition(get_token_pos(), 'right'),
      }
      next_token()
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
        missSymbol('(', node.node.finish, node.node.finish)
      end
      lastMethod = getmethod
    elseif token == '(' then
      if funcName then
        break
      end
      local startPos = getPosition(get_token_pos(), 'left')
      local call = {
        type = 'call',
        start = node.start,
        node = node,
      }
      next_token()
      local args = parseExpList()
      if get_token() == ')' then
        call.finish = getPosition(get_token_pos(), 'right')
        next_token()
      else
        call.finish = lastRightPosition()
        missSymbol(')')
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
            start = bstart,
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
    missSymbol('(', lastMethod.finish)
  end
  return node
end

--- @return parser.object.varargs
local function parseVarargs()
  --- @type parser.object.varargs
  local varargs = {
    type = 'varargs',
    start = getPosition(get_token_pos(), 'left'),
    finish = getPosition(get_token_pos() + 2, 'right'),
  }
  next_token()
  for i = #Chunk, 1, -1 do
    local chunk = Chunk[i]
    if chunk.vararg then
      if not chunk.vararg.ref then
        chunk.vararg.ref = {}
      end
      chunk.vararg.ref[#chunk.vararg.ref + 1] = varargs
      varargs.node = chunk.vararg
      break
    end
    if chunk.type == 'main' then
      break
    elseif chunk.type == 'function' then
      pushError({
        type = 'UNEXPECT_DOTS',
        at = varargs,
      })
      break
    end
  end
  return varargs
end

--- @return parser.object.paren
local function parseParen()
  local pl = get_token_pos()
  --- @type parser.object.paren
  local paren = {
    type = 'paren',
    start = getPosition(pl, 'left'),
    finish = getPosition(pl, 'right'),
  }
  next_token()
  skipSpace()
  local exp = parseExp()
  if exp then
    paren.exp = exp
    paren.finish = exp.finish
    exp.parent = paren
  else
    missExp()
  end
  skipSpace()
  if get_token() == ')' then
    paren.finish = getPosition(get_token_pos(), 'right')
    next_token()
  else
    missSymbol(')')
  end
  return paren
end

local function getLocal(name, pos)
  for i = #Chunk, 1, -1 do
    local chunk = Chunk[i]
    local locals = chunk.locals
    if locals then
      local res
      for n = 1, #locals do
        local loc = locals[n]
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
end

local function resolveName(node)
  if not node then
    return
  end
  local loc = getLocal(node[1], node.start)
  if loc then
    node.type = 'getlocal'
    node.node = loc
    if not loc.ref then
      loc.ref = {}
    end
    loc.ref[#loc.ref + 1] = node
    if loc.special then
      addSpecial(loc.special, node)
    end
  else
    node.type = 'getglobal'
    local env = getLocal(State.ENVMode, node.start)
    if env then
      node.node = env
      if not env.ref then
        env.ref = {}
      end
      env.ref[#env.ref + 1] = node
    end
  end
  local name = node[1]
  bindSpecial(node, name)
  return node
end

local function isChunkFinishToken(token)
  local currentChunk = Chunk[#Chunk]
  if not currentChunk then
    return false
  end
  local tp = currentChunk.type
  if tp == 'main' then
    return false
  end
  if tp == 'for' or tp == 'in' or tp == 'loop' or tp == 'function' then
    return token == 'end'
  end
  if tp == 'if' or tp == 'ifblock' or tp == 'elseifblock' or tp == 'elseblock' then
    return token == 'then' or token == 'end' or token == 'else' or token == 'elseif'
  end
  if tp == 'repeat' then
    return token == 'until'
  end
  return true
end

local parseAction

local function parseActions()
  local rtn, last
  while true do
    skipSpace(true)
    local token = get_token()
    if token == ';' then
      next_token()
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
    pushError({ type = 'ACTION_AFTER_RETURN', at = rtn })
  end
end

local function parseParams(params, isLambda)
  local lastSep
  local hasDots
  local endToken = isLambda and '|' or ')'
  while true do
    skipSpace()
    local token = get_token()
    if not token or token == endToken then
      if lastSep then
        missName()
      end
      break
    elseif token == ',' then
      if lastSep or lastSep == nil then
        missName()
      else
        lastSep = true
      end
      next_token()
    elseif token == '...' then
      if lastSep == false then
        missSymbol(',')
      end
      lastSep = false
      if not params then
        params = {}
      end
      local vararg = {
        type = '...',
        start = getPosition(get_token_pos(), 'left'),
        finish = getPosition(get_token_pos() + #token - 1, 'right'),
        parent = params,
        [1] = '...',
      }
      local chunk = Chunk[#Chunk]
      chunk.vararg = vararg
      params[#params + 1] = vararg
      if hasDots then
        pushError({
          type = 'ARGS_AFTER_DOTS',
          start = getPosition(get_token_pos(), 'left'),
          finish = getPosition(get_token_pos() + #token - 1, 'right'),
        })
      end
      hasDots = true
      next_token()
    elseif CharMapWord[string.sub(token, 1, 1)] then
      if lastSep == false then
        missSymbol(',')
      end
      lastSep = false
      if not params then
        params = {}
      end
      params[#params + 1] = createLocal({
        start = getPosition(get_token_pos(), 'left'),
        finish = getPosition(get_token_pos() + #token - 1, 'right'),
        parent = params,
        [1] = token,
      })
      if hasDots then
        pushError({
          type = 'ARGS_AFTER_DOTS',
          start = getPosition(get_token_pos(), 'left'),
          finish = getPosition(get_token_pos() + #token - 1, 'right'),
        })
      end
      if isKeyWord(token, Tokens[Index + 3]) then
        pushError({
          type = 'KEYWORD',
          start = getPosition(get_token_pos(), 'left'),
          finish = getPosition(get_token_pos() + #token - 1, 'right'),
        })
      end
      next_token()
    else
      skipUnknownSymbol()
    end
  end
  return params
end

local function parseFunction(isLocal, isAction)
  local funcLeft = getPosition(get_token_pos(), 'left')
  local funcRight = getPosition(get_token_pos() + 7, 'right')
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
  next_token()
  skipSpace(true)
  local hasLeftParen = get_token() == '('
  if not hasLeftParen then
    local name = parseName()
    if name then
      local simple = parseSimple(name, true)
      if isLocal then
        if simple == name then
          createLocal(name)
        else
          resolveName(name)
          pushError({ type = 'UNEXPECT_LFUNC_NAME', at = simple.start })
        end
      else
        resolveName(name)
      end
      func.name = simple
      func.finish = simple.finish
      func.bstart = simple.finish
      if not isAction then
        simple.parent = func
        pushError({ type = 'UNEXPECT_EFUNC_NAME', at = simple })
      end
      skipSpace(true)
      hasLeftParen = get_token() == '('
    end
  end
  local LastLocalCount = LocalCount
  LocalCount = 0
  pushChunk(func)
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
    local parenLeft = getPosition(get_token_pos(), 'left')
    next_token()
    params = parseParams(params)
    params.type = 'funcargs'
    params.start = parenLeft
    params.finish = lastRightPosition()
    params.parent = func
    func.args = params
    skipSpace(true)
    if get_token() == ')' then
      local parenRight = getPosition(get_token_pos(), 'right')
      func.finish = parenRight
      func.bstart = parenRight
      if params then
        params.finish = parenRight
      end
      next_token()
      skipSpace(true)
    else
      func.finish = lastRightPosition()
      func.bstart = func.finish
      if params then
        params.finish = func.finish
      end
      missSymbol(')')
    end
  else
    missSymbol('(')
  end
  parseActions()
  popChunk()
  if get_token() == 'end' then
    local endLeft = getPosition(get_token_pos(), 'left')
    local endRight = getPosition(get_token_pos() + 2, 'right')
    func.keyword[3] = endLeft
    func.keyword[4] = endRight
    func.finish = endRight
    next_token()
  else
    func.finish = lastRightPosition()
    missEnd(funcLeft, funcRight)
  end
  LocalCount = LastLocalCount
  return func
end

local function parseLambda(isDoublePipe)
  local lambdaLeft = getPosition(get_token_pos(), 'left')
  local lambdaRight = getPosition(get_token_pos(), 'right')
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
  next_token()
  local pipeLeft = getPosition(get_token_pos(), 'left')
  local pipeRight = getPosition(get_token_pos(), 'right')
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
    pushChunk(lambda)
    LocalCount = 0
    params = parseParams({}, true)
    params.type = 'funcargs'
    params.start = pipeLeft
    params.finish = lastRightPosition()
    params.parent = lambda
    lambda.args = params
    skipSpace()
    if get_token() == '|' then
      pipeRight = getPosition(get_token_pos(), 'right')
      lambda.finish = pipeRight
      lambda.bstart = pipeRight
      if params then
        params.finish = pipeRight
      end
      next_token()
      skipSpace()
    else
      lambda.finish = lastRightPosition()
      lambda.bstart = lambda.finish
      if params then
        params.finish = lambda.finish
      end
      missSymbol('|')
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
    missExp()
  end
  LocalCount = LastLocalCount
  return lambda
end

local function checkNeedParen(source)
  local token = get_token()
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
  local token = get_token()
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
  local token = get_token()
  local symbol = UnarySymbol[token] and token or UnaryAlias[token]
  if not symbol then
    return
  end
  local myLevel = UnarySymbol[symbol]
  local op = {
    type = symbol,
    start = getPosition(get_token_pos(), 'left'),
    finish = getPosition(get_token_pos() + #symbol - 1, 'right'),
  }
  next_token()
  return op, myLevel
end

--- @param level integer # op level must greater than this level
--- @return parser.binop?, integer?
local function parseBinaryOP(asAction, level)
  local token = get_token()
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
  --- @type parser.binop
  local op = {
    type = symbol,
    start = getPosition(get_token_pos(), 'left'),
    finish = getPosition(get_token_pos() + #token - 1, 'right'),
  }
  if not asAction then
    if token == '=' then
      pushError({
        type = 'ERR_EQ_AS_ASSIGN',
        at = op,
        fix = {
          title = 'FIX_EQ_AS_ASSIGN',
          {
            start = op.start,
            finish = op.finish,
            text = '==',
          },
        },
      })
    end
  end
  if BinaryAlias[token] then
    if not State.options.nonstandardSymbol[token] then
      pushError({
        type = 'ERR_NONSTANDARD_SYMBOL',
        at = op,
        info = {
          symbol = symbol,
        },
        fix = {
          title = 'FIX_NONSTANDARD_SYMBOL',
          symbol = symbol,
          {
            start = op.start,
            finish = op.finish,
            text = symbol,
          },
        },
      })
    end
  end
  if token == '//' or token == '<<' or token == '>>' then
    if State.version ~= 'Lua 5.3' and State.version ~= 'Lua 5.4' then
      pushError({
        type = 'UNSUPPORT_SYMBOL',
        version = { 'Lua 5.3', 'Lua 5.4' },
        at = op,
        info = {
          version = State.version,
        },
      })
    end
  end
  next_token()
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
        missExp()
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
        missExp()
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
    if get_token() == ',' then
      missExp()
      next_token()
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
  if get_token() ~= ',' then
    return first
  end
  next_token()
  skipSeps()
  local second = parseExp()
  if not second then
    missExp()
    return first
  end
  skipSpace()
  if get_token() ~= ',' then
    return first, second
  end
  next_token()
  skipSeps()
  local third = parseExp()
  if not third then
    missExp()
    return first, second
  end

  local rest = { third }
  while true do
    skipSpace()
    if get_token() ~= ',' then
      return first, second, rest
    end
    next_token()
    skipSeps()
    local exp = parseExp()
    if not exp then
      missExp()
      return first, second, rest
    end
    rest[#rest + 1] = exp
  end
end

local function pushIntoCurrentChunk(action)
  local chunk = Chunk[#Chunk]
  if chunk then
    chunk[#chunk + 1] = action
    action.parent = chunk
  end
end

--- @return parser.object?   second
--- @return parser.object[]? rest
local function parseVarTails(parser, isLocal)
  if get_token() ~= ',' then
    return nil
  end
  next_token()
  skipSpace()
  local second = parser(true)
  if not second then
    missName()
    return nil
  end
  if isLocal then
    createLocal(second, parseLocalAttrs())
  end
  skipSpace()
  if get_token() ~= ',' then
    return second
  end
  next_token()
  skipSeps()
  local third = parser(true)
  if not third then
    missName()
    return second
  end
  if isLocal then
    createLocal(third, parseLocalAttrs())
  end
  local rest = { third }
  while true do
    skipSpace()
    if get_token() ~= ',' then
      return second, rest
    end
    next_token()
    skipSeps()
    local name = parser(true)
    if not name then
      missName()
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
      missExp()
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
    pushIntoCurrentChunk(n2)
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
      pushIntoCurrentChunk(n)
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
    pushIntoCurrentChunk(v2)
  end
  if vrest then
    for i = 1, #vrest do
      local v = vrest[i]
      if not nrest or not nrest[i] then
        v.redundant = {
          max = max,
          passed = i + 2,
        }
        pushIntoCurrentChunk(v)
      end
    end
  end

  return n1, isSet
end

local function compileExpAsAction(exp)
  pushIntoCurrentChunk(exp)
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
  local locPos = getPosition(get_token_pos(), 'left')
  next_token()
  skipSpace()
  local word = peekWord()
  if not word then
    missName()
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
      pushIntoCurrentChunk(name)
      return name
    else
      missName(func.keyword[2])
      pushIntoCurrentChunk(func)
      return func
    end
  end

  local name = parseName(true)
  if not name then
    missName()
    return
  end
  local loc = createLocal(name, parseLocalAttrs())
  loc.locPos = locPos
  loc.effect = math.maxinteger
  pushIntoCurrentChunk(loc)
  skipSpace()
  parseMultiVars(loc, parseName, true)

  return loc
end

local function parseDo()
  local doLeft = getPosition(get_token_pos(), 'left')
  local doRight = getPosition(get_token_pos() + 1, 'right')
  local obj = {
    type = 'do',
    start = doLeft,
    finish = doRight,
    bstart = doRight,
    keyword = {
      [1] = doLeft,
      [2] = doRight,
    },
  }
  next_token()
  pushIntoCurrentChunk(obj)
  pushChunk(obj)
  parseActions()
  popChunk()
  if get_token() == 'end' then
    obj.finish = getPosition(get_token_pos() + 2, 'right')
    obj.keyword[3] = getPosition(get_token_pos(), 'left')
    obj.keyword[4] = getPosition(get_token_pos() + 2, 'right')
    next_token()
  else
    missEnd(doLeft, doRight)
  end
  if obj.locals then
    LocalCount = LocalCount - #obj.locals
  end

  return obj
end

local function parseReturn()
  local returnLeft = getPosition(get_token_pos(), 'left')
  local returnRight = getPosition(get_token_pos() + 5, 'right')
  next_token()
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
  pushIntoCurrentChunk(rtn)
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
  local left = getPosition(get_token_pos(), 'left')
  next_token()
  skipSpace()
  local name = parseName()
  skipSpace()

  if not name then
    missName()
  end

  if get_token() == '::' then
    next_token()
  elseif name then
    missSymbol('::')
  end

  if not name then
    return
  end

  label = name --[[@as parser.object.label]]
  label.type = 'label'

  pushIntoCurrentChunk(label)

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
  local start = getPosition(get_token_pos(), 'left')
  next_token()
  skipSpace()

  local action = parseName()
  if not action then
    missName()
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

  pushIntoCurrentChunk(action)
  return action
end


--- @param parent parser.object.if
--- @return parser.object.ifblock
local function parseIfBlock(parent)
  local ifLeft = getPosition(get_token_pos(), 'left')
  local ifRight = getPosition(get_token_pos() + 1, 'right')
  next_token()
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
    missExp()
  end
  skipSpace()
  local thenToken = get_token()
  if thenToken == 'then' or thenToken == 'do' then
    obj.finish = getPosition(get_token_pos() + #thenToken - 1, 'right')
    obj.bstart = obj.finish
    obj.keyword[3] = getPosition(get_token_pos(), 'left')
    obj.keyword[4] = obj.finish
    if thenToken == 'do' then
      pushError({
        type = 'ERR_THEN_AS_DO',
        start = obj.keyword[3],
        finish = obj.keyword[4],
        fix = {
          title = 'FIX_THEN_AS_DO',
          {
            start = obj.keyword[3],
            finish = obj.keyword[4],
            text = 'then',
          },
        },
      })
    end
    next_token()
  else
    missSymbol('then')
  end
  pushChunk(obj)
  parseActions()
  popChunk()
  obj.finish = getPosition(get_token_pos(), 'left')
  if obj.locals then
    LocalCount = LocalCount - #obj.locals
  end
  return obj
end

local function parseElseIfBlock(parent)
  local ifLeft = getPosition(get_token_pos(), 'left')
  local ifRight = getPosition(get_token_pos() + 5, 'right')
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
  next_token()
  skipSpace()
  local filter = parseExp()
  if filter then
    elseifblock.filter = filter
    elseifblock.finish = filter.finish
    elseifblock.bstart = elseifblock.finish
    filter.parent = elseifblock
  else
    missExp()
  end
  skipSpace()
  local thenToken = get_token()
  if thenToken == 'then' or thenToken == 'do' then
    elseifblock.finish = getPosition(get_token_pos() + #thenToken - 1, 'right')
    elseifblock.bstart = elseifblock.finish
    elseifblock.keyword[3] = getPosition(get_token_pos(), 'left')
    elseifblock.keyword[4] = elseifblock.finish
    if thenToken == 'do' then
      pushError({
        type = 'ERR_THEN_AS_DO',
        start = elseifblock.keyword[3],
        finish = elseifblock.keyword[4],
        fix = {
          title = 'FIX_THEN_AS_DO',
          {
            start = elseifblock.keyword[3],
            finish = elseifblock.keyword[4],
            text = 'then',
          },
        },
      })
    end
    next_token()
  else
    missSymbol('then')
  end
  pushChunk(elseifblock)
  parseActions()
  popChunk()
  elseifblock.finish = getPosition(get_token_pos(), 'left')
  if elseifblock.locals then
    LocalCount = LocalCount - #elseifblock.locals
  end
  return elseifblock
end

local function parseElseBlock(parent)
  local ifLeft = getPosition(get_token_pos(), 'left')
  local ifRight = getPosition(get_token_pos() + 3, 'right')
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
  next_token()
  skipSpace()
  pushChunk(elseblock)
  parseActions()
  popChunk()
  elseblock.finish = getPosition(get_token_pos(), 'left')
  if elseblock.locals then
    LocalCount = LocalCount - #elseblock.locals
  end
  return elseblock
end

local function parseIf()
  local token = get_token()
  local left = getPosition(get_token_pos(), 'left')
  local obj = {
    type = 'if',
    start = left,
    finish = getPosition(get_token_pos() + #token - 1, 'right'),
  }
  pushIntoCurrentChunk(obj)
  if token ~= 'if' then
    missSymbol('if', left, left)
  end
  local hasElse
  while true do
    local word = get_token()
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

  if get_token() == 'end' then
    obj.finish = getPosition(get_token_pos() + 2, 'right')
    next_token()
  else
    missEnd(obj[1].keyword[1], obj[1].keyword[2])
  end

  return obj
end

--- @return parser.object.for|parser.object.loop|parser.object.in
local function parseFor()
  local start = getPosition(get_token_pos(), 'left')
  local finish = getPosition(get_token_pos() + 2, 'right')
  --- @type parser.object.for
  local action = {
    type = 'for',
    start = start,
    finish = finish,
    keyword = {start, finish},
    bstart = finish,
  }

  next_token()
  pushIntoCurrentChunk(action)
  pushChunk(action)
  skipSpace()
  local nameOrList = parseNameOrList(action)
  if not nameOrList then
    missName()
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
  elseif get_token() == 'in' then
    local forin = action --[[@as parser.object.in]]
    forin.type = 'in'
    local inLeft = getPosition(get_token_pos(), 'left')
    local inRight = getPosition(get_token_pos() + 1, 'right')
    next_token()
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
      missExp()
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
    missSymbol('in')
  end

  skipSpace()
  local doToken = get_token()
  if doToken == 'do' or doToken == 'then' then
    local left = getPosition(get_token_pos(), 'left')
    local right = getPosition(get_token_pos() + #doToken - 1, 'right')
    action.finish = left
    action.bstart = action.finish
    action.keyword[#action.keyword + 1] = left
    action.keyword[#action.keyword + 1] = right
    if doToken == 'then' then
      pushError({
        type = 'ERR_DO_AS_THEN',
        start = left,
        finish = right,
        fix = {
          title = 'FIX_DO_AS_THEN',
          {
            start = left,
            finish = right,
            text = 'do',
          },
        },
      })
    end
    next_token()
  else
    missSymbol('do')
  end

  skipSpace()
  parseActions()
  popChunk()

  skipSpace()
  if get_token() == 'end' then
    action.finish = getPosition(get_token_pos() + 2, 'right')
    action.keyword[#action.keyword + 1] = getPosition(get_token_pos(), 'left')
    action.keyword[#action.keyword + 1] = action.finish
    next_token()
  else
    missEnd(action.keyword[1], action.keyword[2])
  end

  LocalCount = LocalCount - #(action.locals or {})
  LocalCount = LocalCount - (forStateVars or 0)

  return action
end

--- @return parser.object.while
local function parseWhile()
  local start = getPosition(get_token_pos(), 'left')
  local finish = getPosition(get_token_pos() + 4, 'right')
  --- @type parser.object.while
  local action = {
    type = 'while',
    start = start,
    finish = finish,
    keyword = {start, finish},
    bstart = finish
  }
  next_token()

  skipSpace()
  local nextToken = get_token()
  local filter = nextToken ~= 'do' and nextToken ~= 'then' and parseExp()
  if filter then
    action.filter = filter
    action.finish = filter.finish
    filter.parent = action
  else
    missExp()
  end

  skipSpace()
  local doToken = get_token()
  if doToken == 'do' or doToken == 'then' then
    local left = getPosition(get_token_pos(), 'left')
    local right = getPosition(get_token_pos() + #doToken - 1, 'right')
    action.finish = left
    action.bstart = left
    action.keyword[#action.keyword + 1] = left
    action.keyword[#action.keyword + 1] = right
    if doToken == 'then' then
      pushError({
        type = 'ERR_DO_AS_THEN',
        start = left,
        finish = right,
        fix = {
          title = 'FIX_DO_AS_THEN',
          {
            start = left,
            finish = right,
            text = 'do',
          },
        },
      })
    end
    next_token()
  else
    missSymbol('do')
  end

  pushIntoCurrentChunk(action)
  pushChunk(action)
  skipSpace()
  parseActions()
  popChunk()

  skipSpace()
  if get_token() == 'end' then
    action.finish = getPosition(get_token_pos() + 2, 'right')
    action.keyword[#action.keyword + 1] = getPosition(get_token_pos(), 'left')
    action.keyword[#action.keyword + 1] = action.finish
    next_token()
  else
    missEnd(action.keyword[1], action.keyword[2])
  end

  LocalCount = LocalCount - #(action.locals or {})

  return action
end

local function parseRepeat()
  local action = {
    type = 'repeat',
    start = getPosition(get_token_pos(), 'left'),
    finish = getPosition(get_token_pos() + 5, 'right'),
    keyword = {},
  }
  action.bstart = action.finish
  action.keyword[1] = action.start
  action.keyword[2] = action.finish
  next_token()

  pushIntoCurrentChunk(action)
  pushChunk(action)
  skipSpace()
  parseActions()

  skipSpace()
  if get_token() == 'until' then
    action.finish = getPosition(get_token_pos() + 4, 'right')
    action.keyword[#action.keyword + 1] = getPosition(get_token_pos(), 'left')
    action.keyword[#action.keyword + 1] = action.finish
    next_token()

    skipSpace()
    local filter = parseExp()
    if filter then
      action.filter = filter
      filter.parent = action
    else
      missExp()
    end
  else
    missSymbol('until')
  end

  popChunk()
  if action.filter then
    action.finish = action.filter.finish
  end

  if action.locals then
    LocalCount = LocalCount - #action.locals
  end

  return action
end

local function parseBreak()
  local returnLeft = getPosition(get_token_pos(), 'left')
  local returnRight = getPosition(get_token_pos() + #get_token() - 1, 'right')
  next_token()
  skipSpace()
  local action = {
    type = 'break',
    start = returnLeft,
    finish = returnRight,
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

  pushIntoCurrentChunk(action)
  return action
end

--- @return parser.object.union? action
--- @return true? err
function parseAction()
  local token = get_token()

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
  elseif token == 'goto' and isKeyWord('goto', Tokens[Index + 3]) then
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
      pushIntoCurrentChunk(name)
      return name
    else
      pushIntoCurrentChunk(exp)
      missName(exp.keyword[2])
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
  if get_token() ~= '#' then
    return
  end
  while true do
    next_token()
    local token = get_token()
    if not token then
      break
    end
    if NLMap[token] then
      skipNL()
      break
    end
  end
end

--- @class parser.object.main : parser.object.base
--- @field type 'main'

--- @return parser.object.main
local function parseLua()
  local main = {
    type = 'main',
    start = 0,
    finish = 0,
  }
  pushChunk(main)
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
    if Index <= #Tokens then
      unknownSymbol()
      next_token()
    else
      break
    end
  end
  popChunk()
  main.finish = getPosition(#Lua, 'right')

  return main
end

local function initState(lua, version, options)
  Lua = lua
  Line = 0
  LineOffset = 1
  LastTokenFinish = 0
  LocalCount = 0
  LocalLimited = false
  Chunk = {}
  Tokens = tokens(lua)
  Index = 1

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
    if Index <= #Tokens then
      unknownSymbol()
      next_token()
    else
      break
    end
  end

  return State
end
