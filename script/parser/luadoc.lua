local m = require('lpeglabel')
local re = require('parser.relabel')
local guide = require('parser.guide')
local compile = require('parser.compile')
local util = require('utility')

--- @class parser.object.doc.base
--- @field start integer
--- @field finish integer
--- @field parent? parser.object.doc
--- @field comment? string|parser.object.comment|parser.object.doc.tailcomment
--- @field range? integer
--- @field virtual? true
--- @field special? parser.object
--- @field originalComment? parser.object.comment.short
--- @field specialBindGroup? parser.object.doc[]
--- @field bindGroup? parser.object.doc[]

--- @alias parser.object.doc
--- | parser.object.doc.alias
--- | parser.object.doc.as
--- | parser.object.doc.async
--- | parser.object.doc.cast
--- | parser.object.doc.cast.name
--- | parser.object.doc.class
--- | parser.object.doc.deprecated
--- | parser.object.doc.diagnostic
--- | parser.object.doc.enum
--- | parser.object.doc.field
--- | parser.object.doc.field.name
--- | parser.object.doc.generic
--- | parser.object.doc.generic.object
--- | parser.object.doc.meta
--- | parser.object.doc.module
--- | parser.object.doc.nodiscard
--- | parser.object.doc.operator
--- | parser.object.doc.overload
--- | parser.object.doc.package
--- | parser.object.doc.see
--- | parser.object.doc.param
--- | parser.object.doc.private
--- | parser.object.doc.protected
--- | parser.object.doc.public
--- | parser.object.doc.return
--- | parser.object.doc.source
--- | parser.object.doc.type
--- | parser.object.doc.type.name
--- | parser.object.doc.type.unit
--- | parser.object.doc.type.field
--- | parser.object.doc.type.arg
--- | parser.object.doc.vararg
--- | parser.object.doc.version
--- | parser.object.doc.comment

--- @class parser.object.doc.main
--- @field type 'doc'
--- @field parent parser.object
--- @field groups unknown
--- @field start? integer
--- @field finish? integer
--- @field [integer] parser.object.doc

--- @class parser.object.doc.type.sign
--- @field type 'doc.type.sign'
--- @field node parser.object.doc.type.unit
--- @field signs parser.object.doc.type[]

--- @class parser.object.doc.alias : parser.object.doc.base
--- @field type 'doc.alias'
--- @field alias? parser.object.doc.alias.name
--- @field docAttr? parser.object.doc.attr
--- @field extends? parser.object.doc.type
--- @field signs? parser.object.doc.generic.name[]

--- @class parser.object.doc.alias.name : parser.object.doc.base
--- @field type 'doc.alias.name'
--- @field [1] string

--- @class parser.object.doc.as : parser.object.doc.base
--- @field type 'doc.as'
--- @field as? parser.object.doc.type
--- @field touch? integer

--- @class parser.object.doc.enum : parser.object.doc.base
--- @field type 'doc.enum'
--- @field enum parser.object.doc.enum.name
--- @field docAttr? parser.object.doc.attr

--- @class parser.object.doc.enum.name : parser.object.doc.base
--- @field type 'doc.enum.name'
--- @field [1] string

--- @class parser.object.doc.async : parser.object.doc.base
--- @field type 'doc.async'

--- @class parser.object.doc.cast : parser.object.doc.base
--- @field type 'doc.cast'
--- @field name? parser.object.doc.cast.name
--- @field casts parser.object.doc.cast.block[]

--- @class parser.object.doc.cast.name : parser.object.doc.base
--- @field type 'doc.cast.name'
--- @field [1] string

--- @class parser.object.doc.cast.block : parser.object.doc.base
--- @field type 'doc.cast.block'
--- @field mode? '+'|'-'
--- @field optional? true
--- @field extends? parser.object.doc.type

--- @class parser.object.doc.class : parser.object.doc.base
--- @field type 'doc.class'
--- @field class? parser.object.doc.class.name
--- @field docAttr? parser.object.doc.attr
--- @field fields unknown
--- @field operators unknown
--- @field calls unknown
--- @field signs? parser.object.doc.generic.name[]
--- @field extends? (parser.object.doc.extends.name|parser.object.doc.type.table)[]

--- @class parser.object.doc.class.name : parser.object.doc.base
--- @field type 'doc.class.name'

--- @class parser.object.doc.extends.name : parser.object.doc.base
--- @field type 'doc.extends.name'

--- @class parser.object.doc.type.arg : parser.object.doc.base
--- @field type 'doc.type.arg'
--- @field name? parser.object.doc.type.arg.name
--- @field optional? true
--- @field extends? parser.object.doc.type
---
--- @class parser.object.doc.type.arg.name : parser.object.doc.base
--- @field type 'doc.type.arg.name'

--- @class parser.object.doc.comment : parser.object.doc.base
--- @field type 'doc.comment'

--- @class parser.object.doc.deprecated : parser.object.doc.base
--- @field type 'doc.deprecated'

--- @class parser.object.doc.meta : parser.object.doc.base
--- @field type 'doc.meta'
--- @field name? parser.object.doc.meta.name
---
--- @class parser.object.doc.meta.name : parser.object.doc.base
--- @field type 'doc.meta.name'
--- @field [1] string

--- @class parser.object.doc.diagnostic : parser.object.doc.base
--- @field type 'doc.diagnostic'
--- @field mode? string
--- @field names? parser.object.doc.diagnostic.name[]

--- @class parser.object.doc.diagnostic.name : parser.object.doc.base
--- @field type 'doc.diagnostic.name'
--- @field [1] string

--- @class parser.object.doc.field : parser.object.doc.base
--- @field type 'doc.field'
--- @field optional? true
--- @field extends? parser.object.doc.type
--- @field visible? 'public'|'protected'|'private'|'package'
--- @field field? parser.object.doc.field.name|parser.object.doc.type

--- @class parser.object.doc.generic : parser.object.doc.base
--- @field type 'doc.generic'
--- @field generics parser.object.doc.generic.object[]

--- @class parser.object.doc.generic.object: parser.object.doc.base
--- @field type 'doc.generic.object'
--- @field parent parser.object.doc.generic
--- @field generic parser.object.doc.generic.name
--- @field extends? parser.object.doc.type

--- @class parser.object.doc.generic.name : parser.object.doc.base
--- @field type 'doc.generic.name'
--- @field parent parser.object.doc.generic.object
--- @field generic? parser.object.doc.generic.object
--- @field literal? true
--- @field [1] string

--- @class parser.object.doc.module : parser.object.doc.base
--- @field type 'doc.module'
--- @field module? string
--- @field smark? string

--- @class parser.object.doc.nodiscard : parser.object.doc.base
--- @field type 'doc.nodiscard'

--- @class parser.object.doc.operator : parser.object.doc.base
--- @field type 'doc.operator'
--- @field op? parser.object.doc.operator.name
--- @field exp? parser.object.doc.type
--- @field extends? parser.object.doc.type

--- @class parser.object.doc.operator.name : parser.object.doc.base
--- @field type 'doc.operator.name'
--- @field [1] string

--- @class parser.object.doc.overload : parser.object.doc.base
--- @field type 'doc.overload'
--- @field overload? parser.object.doc.type.function

--- @class parser.object.doc.package : parser.object.doc.base
--- @field type 'doc.package'

--- @class parser.object.doc.param : parser.object.doc.base
--- @field type 'doc.param'
--- @field param? parser.object.doc.param.name
--- @field extends? parser.object.doc.type
--- @field optional? true
--- @field firstFinish? integer

--- @class parser.object.doc.param.name : parser.object.doc.base
--- @field type 'doc.param.name'
--- @field [1] string

--- @class parser.object.doc.private : parser.object.doc.base
--- @field type 'doc.private'

--- @class parser.object.doc.protected : parser.object.doc.base
--- @field type 'doc.protected'

--- @class parser.object.doc.public : parser.object.doc.base
--- @field type 'doc.public'

--- @class parser.object.doc.return : parser.object.doc.base
--- @field type 'doc.return'
--- @field returns parser.object.doc.type[]

--- @class parser.object.doc.return.name : parser.object.doc.base
--- @field type 'doc.return.name'
--- @field [1] string

--- @class parser.object.doc.see : parser.object.doc.base
--- @field type 'doc.see'
--- @field name? parser.object.doc.see.name

--- @class parser.object.doc.see.name : parser.object.doc.base
--- @field type 'doc.see.name'
--- @field [1] string

--- @class parser.object.doc.source : parser.object.doc.base
--- @field type 'doc.source'

--- @class parser.object.doc.tailcomment : parser.object.doc.base
--- @field type 'doc.tailcomment'

--- @class parser.object.doc.attr : parser.object.doc.base
--- @field type 'doc.attr'
--- @field names parser.object.doc.attr.name[]

--- @class parser.object.doc.attr.name : parser.object.doc.base
--- @field type 'doc.attr.name'
--- @field [1] string

--- @alias parser.object.doc.type.unit
--- | parser.object.doc.type
--- | parser.object.doc.type.boolean
--- | parser.object.doc.type.code
--- | parser.object.doc.type.function
--- | parser.object.doc.type.integer
--- | parser.object.doc.type.name
--- | parser.object.doc.type.string
--- | parser.object.doc.type.table
--- | parser.object.doc.type.array
--- | parser.object.doc.type.sign

--- @class parser.object.doc.type : parser.object.doc.base
--- @field type 'doc.type'
--- @field parent parser.object.doc
--- @field types parser.object.doc.type.unit[]
--- @field optional? true
--- @field firstFinish integer
--- @field name? parser.object.doc.return.name

--- @class parser.object.doc.type.array : parser.object.doc.base
--- @field type 'doc.type.array'
--- @field node parser.object.doc.type.unit

--- @class parser.object.doc.type.code : parser.object.doc.base
--- @field type 'doc.type.code'
--- @field [1] string

--- @class parser.object.doc.type.name : parser.object.doc.base
--- @field type 'doc.type.name'
--- @field [1] string

--- @class parser.object.doc.type.boolean : parser.object.doc.base
--- @field type 'doc.type.boolean'
--- @field [1] boolean

--- @class parser.object.doc.type.string : parser.object.doc.base
--- @field type 'doc.type.string'
--- @field [1] string

--- @class parser.object.doc.type.integer : parser.object.doc.base
--- @field type 'doc.type.integer'
--- @field [1] integer

--- @class parser.object.doc.type.table : parser.object.doc.base
--- @field type 'doc.type.table'
--- @field fields parser.object.doc.type.field[]

--- @class parser.object.doc.type.function : parser.object.doc.base
--- @field type 'doc.type.function'
--- @field args parser.object.doc.type.arg[]
--- @field returns parser.object.doc.type[]
--- @field async? true
--- @field asyncPos? integer

--- @class parser.object.doc.type.field : parser.object.doc.base
--- @field type 'doc.type.field'
--- @field parent parser.object.doc.type.table
--- @field name? parser.object.doc.field.name|parser.object.doc.type
--- @field extends? parser.object.doc.type
--- @field optional? true

--- @class parser.object.doc.field.name : parser.object.doc.base
--- @field type 'doc.field.name'

--- @class parser.object.doc.vararg : parser.object.doc.base
--- @field type 'doc.vararg'
--- @field vararg? parser.object.doc.type

--- @class parser.object.doc.version : parser.object.doc.base
--- @field type 'doc.version'
--- @field versions parser.object.doc.version.unit[]
---
--- @class parser.object.doc.version.unit : parser.object.doc.base
--- @field type 'doc.version.unit'
--- @field le? true
--- @field ge? true
--- @field version? number|string

local TokenTypes, TokenStarts, TokenFinishs, TokenContents
local TokenMarks --- @type table<integer,string?>?
--- @type integer
local Ci
--- @type integer
local Offset
local pushWarning, NextComment, Lines
local parseType, parseTypeUnit
--- @type any
local Parser = re.compile(
    [[
Main                <-  (Token / Sp)*
Sp                  <-  %s+
X16                 <-  [a-fA-F0-9]
Token               <-  Integer / Name / String / Code / Symbol
Name                <-  ({} {%name} {})
                    ->  Name
Integer             <-  ({} {'-'? [0-9]+} !'.' {})
                    ->  Integer
Code                <-  ({} '`' { (!'`' .)*} '`' {})
                    ->  Code
String              <-  ({} StringDef {})
                    ->  String
StringDef           <-  {'"'}
                        {~(Esc / !'"' .)*~} -> 1
                        ('"'?)
                    /   {"'"}
                        {~(Esc / !"'" .)*~} -> 1
                        ("'"?)
                    /   '[' {:eq: '='* :} '['
                        =eq -> LongStringMark
                        {(!StringClose .)*} -> 1
                        StringClose?
StringClose         <-  ']' =eq ']'
Esc                 <-  '\' -> ''
                        EChar
EChar               <-  'a' -> ea
                    /   'b' -> eb
                    /   'f' -> ef
                    /   'n' -> en
                    /   'r' -> er
                    /   't' -> et
                    /   'v' -> ev
                    /   '\'
                    /   '"'
                    /   "'"
                    /   %nl
                    /   ('z' (%nl / %s)*)     -> ''
                    /   ('x' {X16 X16})       -> Char16
                    /   ([0-9] [0-9]? [0-9]?) -> Char10
                    /   ('u{' {X16*} '}')    -> CharUtf8
Symbol              <-  ({} {
                            [:|,;<>()?+#{}]
                        /   '[]'
                        /   '...'
                        /   '['
                        /   ']'
                        /   '-' !'-'
                        } {})
                    ->  Symbol
]],
    {
        s = m.S(' \t\v\f'),
        ea = '\a',
        eb = '\b',
        ef = '\f',
        en = '\n',
        er = '\r',
        et = '\t',
        ev = '\v',
        name = (m.R('az', 'AZ', '09', '\x80\xff') + m.S('_'))
            * (m.R('az', 'AZ', '__', '09', '\x80\xff') + m.S('_.*-')) ^ 0,
        Char10 = function(char)
            ---@type integer?
            char = tonumber(char)
            if not char or char < 0 or char > 255 then
                return ''
            end
            return string.char(char)
        end,
        Char16 = function(char)
            return string.char(tonumber(char, 16))
        end,
        CharUtf8 = function(char)
            if #char == 0 then
                return ''
            end
            local v = tonumber(char, 16)
            if not v then
                return ''
            end
            if v >= 0 and v <= 0x10FFFF then
                return utf8.char(v)
            end
            return ''
        end,
        LongStringMark = function(back)
            return '[' .. back .. '['
        end,
        Name = function(start, content, finish)
            Ci = Ci + 1
            TokenTypes[Ci] = 'name'
            TokenStarts[Ci] = start
            TokenFinishs[Ci] = finish - 1
            TokenContents[Ci] = content
        end,
        String = function(start, mark, content, finish)
            Ci = Ci + 1
            TokenTypes[Ci] = 'string'
            TokenStarts[Ci] = start
            TokenFinishs[Ci] = finish - 1
            TokenContents[Ci] = content
            TokenMarks[Ci] = mark
        end,
        Integer = function(start, content, finish)
            Ci = Ci + 1
            TokenTypes[Ci] = 'integer'
            TokenStarts[Ci] = start
            TokenFinishs[Ci] = finish - 1
            TokenContents[Ci] = math.tointeger(content)
        end,
        Code = function(start, content, finish)
            Ci = Ci + 1
            TokenTypes[Ci] = 'code'
            TokenStarts[Ci] = start
            TokenFinishs[Ci] = finish - 1
            TokenContents[Ci] = content
        end,
        Symbol = function(start, content, finish)
            Ci = Ci + 1
            TokenTypes[Ci] = 'symbol'
            TokenStarts[Ci] = start
            TokenFinishs[Ci] = finish - 1
            TokenContents[Ci] = content
        end,
    }
)

--- @alias parser.visibleType 'public' | 'protected' | 'private' | 'package'

--- @class parser.object.old
--- @field literal           boolean
--- @field signs             parser.object.base[]
--- @field originalComment   parser.object.base
--- @field as?               parser.object.base
--- @field touch?            integer
--- @field module?           string
--- @field async?            boolean
--- @field names?            parser.object.base[]
--- @field path?             string
--- @field bindComments?     parser.object.base[]
--- @field visible?          parser.visibleType
--- @field operators?        parser.object.base[]
--- @field calls?            parser.object.base[]
--- @field generic?          parser.object.base
--- @field docAttr?          parser.object.base
--- @field pattern?          string

local function parseTokens(text, offset)
    Ci = 0
    Offset = offset
    TokenTypes = {}
    TokenStarts = {}
    TokenFinishs = {}
    TokenContents = {}
    TokenMarks = {}
    Parser:match(text)
    Ci = 0
end

local function peekToken(offset)
    offset = offset or 1
    return TokenTypes[Ci + offset], TokenContents[Ci + offset]
end

--- @return string? tokenType
--- @return string? tokenContent
local function nextToken()
    Ci = Ci + 1
    if not TokenTypes[Ci] then
        Ci = Ci - 1
        return
    end
    return TokenTypes[Ci], TokenContents[Ci]
end

local function checkToken(tp, content, offset)
    offset = offset or 0
    return TokenTypes[Ci + offset] == tp and TokenContents[Ci + offset] == content
end

local function getStart()
    if Ci == 0 then
        return Offset
    end
    return TokenStarts[Ci] + Offset
end

--- @return integer
local function getFinish()
    if Ci == 0 then
        return Offset
    end
    return TokenFinishs[Ci] + Offset + 1
end

local function getMark()
    --- @cast TokenMarks -?
    return TokenMarks[Ci]
end

local function try(callback)
    local savePoint = Ci
    -- rollback
    local suc = callback()
    if not suc then
        Ci = savePoint
    end
    return suc
end

local function parseName(tp, parent)
    local nameTp, nameText = peekToken()
    if nameTp ~= 'name' then
        return
    end
    nextToken()
    local name = {
        type = tp,
        start = getStart(),
        finish = getFinish(),
        parent = parent,
        [1] = nameText,
    }
    return name
end

local function nextSymbolOrError(symbol)
    if checkToken('symbol', symbol, 1) then
        nextToken()
        return true
    end
    pushWarning({
        type = 'LUADOC_MISS_SYMBOL',
        start = getFinish(),
        finish = getFinish(),
        info = {
            symbol = symbol,
        },
    })
    return false
end

local function parseDots(tp, parent)
    if not checkToken('symbol', '...', 1) then
        return
    end
    nextToken()
    local dots = {
        type = tp,
        start = getStart(),
        finish = getFinish(),
        parent = parent,
        [1] = '...',
    }
    return dots
end

--- @return parser.object.doc.attr.name?
local function parseAttrName(parent)
    return parseName('doc.attr.name', parent)
end

--- @return parser.object.doc.return.name?
local function parseReturnName(parent)
    return parseName('doc.return.name', parent) or parseDots('doc.return.name', parent)
end

--- @return parser.object.doc.type.name?
local function parseTypeName(parent)
    return parseName('doc.type.name', parent) or parseDots('doc.type.name', parent)
end

--- @return parser.object.doc.class.name?
local function parseClassName(parent)
    return parseName('doc.class.name', parent)
end

--- @return parser.object.doc.extends.name?
local function parseExtendsName(parent)
    return parseName('doc.extends.name', parent)
end

--- @return parser.object.doc.alias.name?
local function parseAliasName(parent)
    return parseName('doc.alias.name', parent)
end

--- @return parser.object.doc.field.name?
local function parseFieldName(parent)
    return parseName('doc.field.name', parent)
end

--- @return parser.object.doc.generic.name?
local function parseGenericName(parent)
    return parseName('doc.generic.name', parent)
end

--- @return parser.object.doc.param.name?
local function parseParamName(parent)
    return parseName('doc.param.name', parent) or parseDots('doc.param.name', parent)
end

--- @return parser.object.doc.type.arg.name?
local function parseArgName(parent)
    return parseName('doc.type.arg.name', parent) or parseDots('doc.type.arg.name', parent)
end

--- @return parser.object.doc.meta.name?
local function parseMetaName(parent)
    return parseName('doc.meta.name', parent)
end

--- @return parser.object.doc.see.name?
local function parseSeeName(parent)
    return parseName('doc.see.name', parent)
end

--- @return parser.object.doc.attr?
local function parseDocAttr(parent)
    if not checkToken('symbol', '(', 1) then
        return
    end
    nextToken()

    --- @type parser.object.doc.attr
    local attrs = {
        type = 'doc.attr',
        parent = parent,
        start = getStart(),
        finish = getStart(),
        names = {},
    }

    while true do
        if checkToken('symbol', ',', 1) then
            nextToken()
        else
            local name = parseAttrName(attrs)
            if not name then
                break
            end
            attrs.names[#attrs.names + 1] = name
            attrs.finish = name.finish
        end
    end

    nextSymbolOrError(')')
    attrs.finish = getFinish()

    return attrs
end

--- @return parser.object.doc.type?
local function parseIndexField(parent)
    if not checkToken('symbol', '[', 1) then
        return
    end
    nextToken()
    local field = parseType(parent)
    nextSymbolOrError(']')
    return field
end

--- @return parser.object.doc.type.table?
local function parseTable(parent)
    if not checkToken('symbol', '{', 1) then
        return
    end
    nextToken()
    --- @type parser.object.doc.type.table
    local typeUnit = {
        type = 'doc.type.table',
        start = getStart(),
        parent = parent,
        fields = {},
    }

    while true do
        if checkToken('symbol', '}', 1) then
            nextToken()
            break
        end
        --- @type parser.object.doc.type.field
        local field = {
            type = 'doc.type.field',
            parent = typeUnit,
        }

        do
            local needCloseParen
            if checkToken('symbol', '(', 1) then
                nextToken()
                needCloseParen = true
            end
            field.name = parseFieldName(field) or parseIndexField(field)
            if not field.name then
                pushWarning({
                    type = 'LUADOC_MISS_FIELD_NAME',
                    start = getFinish(),
                    finish = getFinish(),
                })
                break
            end
            field.start = field.start or field.name.start
            if checkToken('symbol', '?', 1) then
                nextToken()
                field.optional = true
            end
            field.finish = getFinish()
            if not nextSymbolOrError(':') then
                break
            end
            field.extends = parseType(field)
            if not field.extends then
                break
            end
            field.finish = getFinish()
            if needCloseParen then
                nextSymbolOrError(')')
            end
        end

        typeUnit.fields[#typeUnit.fields + 1] = field
        if checkToken('symbol', ',', 1) or checkToken('symbol', ';', 1) then
            nextToken()
        else
            nextSymbolOrError('}')
            break
        end
    end
    typeUnit.finish = getFinish()
    return typeUnit
end

--- @return parser.object.doc.type.table?
local function parseTuple(parent)
    if not checkToken('symbol', '[', 1) then
        return
    end
    nextToken()
    --- @type parser.object.doc.type.table
    local typeUnit = {
        type = 'doc.type.table',
        start = getStart(),
        parent = parent,
        fields = {},
        isTuple = true,
    }

    local index = 1
    while true do
        if checkToken('symbol', ']', 1) then
            nextToken()
            break
        end
        --- @type parser.object.doc.type.field
        local field = {
            type = 'doc.type.field',
            parent = typeUnit,
        }

        do
            local needCloseParen
            if checkToken('symbol', '(', 1) then
                nextToken()
                needCloseParen = true
            end
            --- @type parser.object.doc.type
            field.name = {
                type = 'doc.type',
                start = getFinish(),
                firstFinish = getFinish(),
                finish = getFinish(),
                parent = field,
                types = {},
            }
            --- @diagnostic disable-next-line:inject-field
            field.name.types = {
                --- @type parser.object.doc.type.integer
                [1] = {
                    type = 'doc.type.integer',
                    start = getFinish(),
                    finish = getFinish(),
                    parent = field.name,
                    [1] = index,
                },
            }
            index = index + 1
            field.extends = parseType(field)
            if not field.extends then
                break
            end
            field.optional = field.extends.optional
            field.start = field.extends.start
            field.finish = field.extends.finish
            if needCloseParen then
                nextSymbolOrError(')')
            end
        end

        typeUnit.fields[#typeUnit.fields + 1] = field
        if checkToken('symbol', ',', 1) or checkToken('symbol', ';', 1) then
            nextToken()
        else
            nextSymbolOrError(']')
            break
        end
    end
    typeUnit.finish = getFinish()
    return typeUnit
end

local function parseSigns(parent)
    if not checkToken('symbol', '<', 1) then
        return
    end
    nextToken()
    local signs = {}
    while true do
        local sign = parseGenericName(parent)
        if not sign then
            pushWarning({
                type = 'LUADOC_MISS_SIGN_NAME',
                start = getFinish(),
                finish = getFinish(),
            })
            break
        end
        signs[#signs + 1] = sign
        if checkToken('symbol', ',', 1) then
            nextToken()
        else
            break
        end
    end
    nextSymbolOrError('>')
    return signs
end

--- @return parser.object.doc.type.function?
local function parseTypeUnitFunction(parent)
    if not checkToken('name', 'fun', 1) then
        return
    end
    nextToken()
    local typeUnit = {
        type = 'doc.type.function',
        parent = parent,
        start = getStart(),
        args = {},
        returns = {},
    }
    if not nextSymbolOrError('(') then
        return
    end
    while true do
        if checkToken('symbol', ')', 1) then
            nextToken()
            break
        end
        --- @type parser.object.doc.type.arg
        local arg = {
            type = 'doc.type.arg',
            parent = typeUnit,
        }
        arg.name = parseArgName(arg)
        if not arg.name then
            pushWarning({
                type = 'LUADOC_MISS_ARG_NAME',
                start = getFinish(),
                finish = getFinish(),
            })
            break
        end
        if not arg.start then
            arg.start = arg.name.start
        end
        if checkToken('symbol', '?', 1) then
            nextToken()
            arg.optional = true
        end
        arg.finish = getFinish()
        if checkToken('symbol', ':', 1) then
            nextToken()
            arg.extends = parseType(arg)
        end
        arg.finish = getFinish()
        typeUnit.args[#typeUnit.args + 1] = arg
        if checkToken('symbol', ',', 1) then
            nextToken()
        else
            nextSymbolOrError(')')
            break
        end
    end
    if checkToken('symbol', ':', 1) then
        nextToken()
        local needCloseParen
        if checkToken('symbol', '(', 1) then
            nextToken()
            needCloseParen = true
        end
        while true do
            local name
            try(function()
                local returnName = parseReturnName(typeUnit)
                if not returnName then
                    return false
                end
                if checkToken('symbol', ':', 1) then
                    nextToken()
                    name = returnName
                    return true
                end
                if returnName[1] == '...' then
                    name = returnName
                    return false
                end
                return false
            end)
            local rtn = parseType(typeUnit)
            if not rtn then
                break
            end
            rtn.name = name
            if checkToken('symbol', '?', 1) then
                nextToken()
                rtn.optional = true
            end
            typeUnit.returns[#typeUnit.returns + 1] = rtn
            if checkToken('symbol', ',', 1) then
                nextToken()
            else
                break
            end
        end
        if needCloseParen then
            nextSymbolOrError(')')
        end
    end
    typeUnit.finish = getFinish()
    return typeUnit
end

--- @return parser.object.doc.type.function?
local function parseFunction(parent)
    local _, content = peekToken()
    if content == 'async' then
        nextToken()
        local pos = getStart()
        local tp, cont = peekToken()
        if tp == 'name' and cont == 'fun' then
            local func = parseTypeUnit(parent)
            --- @cast func parser.object.doc.type.function
            if func then
                func.async = true
                func.asyncPos = pos
                return func
            end
        end
    elseif content == 'fun' then
        return parseTypeUnitFunction(parent)
    end
end

--- @param parent parser.object.doc
--- @param node parser.object.doc.type.unit
--- @return parser.object.doc.type.array?
local function parseTypeUnitArray(parent, node)
    if not checkToken('symbol', '[]', 1) then
        return
    end
    nextToken()
    --- @type parser.object.doc.type.array
    local result = {
        type = 'doc.type.array',
        start = node.start,
        finish = getFinish(),
        node = node,
        parent = parent,
    }
    node.parent = result
    return result
end

--- @param parent parser.object.doc
--- @param node parser.object.doc.type.unit
--- @return parser.object.doc.type.sign?
local function parseTypeUnitSign(parent, node)
    if not checkToken('symbol', '<', 1) then
        return
    end
    nextToken()
    --- @type parser.object.doc.type.sign
    local result = {
        type = 'doc.type.sign',
        start = node.start,
        finish = getFinish(),
        node = node,
        parent = parent,
        signs = {},
    }
    node.parent = result
    while true do
        local sign = parseType(result)
        if not sign then
            pushWarning({
                type = 'LUA_DOC_MISS_SIGN',
                start = getFinish(),
                finish = getFinish(),
            })
            break
        end
        result.signs[#result.signs + 1] = sign
        if checkToken('symbol', ',', 1) then
            nextToken()
        else
            break
        end
    end
    nextSymbolOrError('>')
    result.finish = getFinish()
    return result
end

--- @return parser.object.doc.type.string?
local function parseString(parent)
    local tp, content = peekToken()
    if not tp or tp ~= 'string' then
        return
    end

    nextToken()
    local mark = getMark()
    -- compatibility
    if content:sub(1, 1) == '"' or content:sub(1, 1) == "'" then
        if #content > 1 and content:sub(1, 1) == content:sub(-1, -1) then
            mark = content:sub(1, 1)
            content = content:sub(2, -2)
        end
    end
    local str = {
        type = 'doc.type.string',
        start = getStart(),
        finish = getFinish(),
        parent = parent,
        [1] = content,
        [2] = mark,
    }
    return str
end

--- @return parser.object.doc.type.code?
local function parseCode(parent)
    local tp, content = peekToken()
    if not tp or tp ~= 'code' then
        return
    end
    nextToken()
    local code = {
        type = 'doc.type.code',
        start = getStart(),
        finish = getFinish(),
        parent = parent,
        [1] = content,
    }
    return code
end

--- @return parser.object.doc.type.code?
local function parseCodePattern(parent)
    local tp, pattern = peekToken()
    if not tp or tp ~= 'name' then
        return
    end
    local codeOffset
    local finishOffset
    local content
    for i = 2, 8 do
        local next, nextContent = peekToken(i)
        if not next or TokenFinishs[Ci + i - 1] + 1 ~= TokenStarts[Ci + i] then
            if codeOffset then
                finishOffset = i
                break
            end
            -- Discontinuous name, invalid
            return
        end
        if next == 'code' then
            if codeOffset and content ~= nextContent then
                -- Multiple generics are not supported for the time being.
                return
            end
            codeOffset = i
            pattern = pattern .. '%s'
            content = nextContent
        elseif next ~= 'name' then
            return
        else
            pattern = pattern .. nextContent
        end
    end

    local start = getStart()

    for _ = 2, finishOffset do
        nextToken()
    end

    --- @type parser.object.doc.type.code
    return {
        type = 'doc.type.code',
        start = start,
        finish = getFinish(),
        parent = parent,
        pattern = pattern,
        [1] = content,
    }
end

--- @return parser.object.doc.type.integer?
local function parseInteger(parent)
    local tp, content = peekToken()
    if not tp or tp ~= 'integer' then
        return
    end

    nextToken()
    --- @type parser.object.doc.type.integer
    return {
        type = 'doc.type.integer',
        start = getStart(),
        finish = getFinish(),
        parent = parent,
        [1] = content,
    }
end

--- @return parser.object.doc.type.boolean?
local function parseBoolean(parent)
    local tp, content = peekToken()
    if not tp or tp ~= 'name' or (content ~= 'true' and content ~= 'false') then
        return
    end

    nextToken()

    --- @type parser.object.doc.type.boolean
    return {
        type = 'doc.type.boolean',
        start = getStart(),
        finish = getFinish(),
        parent = parent,
        [1] = content == 'true',
    }
end

--- @return parser.object.doc.type?
local function parseParen(parent)
    if not checkToken('symbol', '(', 1) then
        return
    end
    nextToken()
    local tp = parseType(parent)
    nextSymbolOrError(')')
    return tp
end

--- @return parser.object.doc.type.unit?
function parseTypeUnit(parent)
    --- @type parser.object.doc.type.unit?
    local result = parseFunction(parent)
        or parseTable(parent)
        or parseTuple(parent)
        or parseString(parent)
        or parseCode(parent)
        or parseInteger(parent)
        or parseBoolean(parent)
        or parseParen(parent)
        or parseCodePattern(parent)

    if not result then
        result = parseTypeName(parent)
        if not result then
            return
        end
        if result[1] == '...' then
            result[1] = 'unknown'
        end
    end

    while true do
        local newResult = parseTypeUnitSign(parent, result)
        if not newResult then
            break
        end
        result = newResult
    end

    while true do
        local newResult = parseTypeUnitArray(parent, result)
        if not newResult then
            break
        end
        result = newResult
    end

    return result
end

local function parseResume(parent)
    --- Used by alias an enum to mark default and additional types
    local default, additional
    if checkToken('symbol', '>', 1) then
        nextToken()
        default = true
    end

    if checkToken('symbol', '+', 1) then
        nextToken()
        additional = true
    end

    local result = parseTypeUnit(parent)
    if result then
        --- @diagnostic disable-next-line:inject-field
        result.default = default
        --- @diagnostic disable-next-line:inject-field
        result.additional = additional
    end

    return result
end

local lockResume = false

--- @param result parser.object.doc.type
local function doResume(result)
    if lockResume then
        return
    end

    lockResume = true

    local row = guide.rowColOf(result.finish)

    local function pushResume()
        local comments --- @type string[]?
        for i = 0, 100 do
            local nextComm = NextComment(i, 'peek')
            if not nextComm then
                return false
            end

            local text, start = nextComm.text, nextComm.start

            local nextCommRow = guide.rowColOf(start)
            local currentRow = row + i + 1
            if currentRow < nextCommRow then
                return false
            end

            if text:match('^%-%s*%@') then
                return false
            end

            local resumeHead = text:match('^%-%s*%|')
            if resumeHead then
                NextComment(i)
                row = row + i + 1
                local finishPos = text:find('#', #resumeHead + 1) or #text
                parseTokens(text:sub(#resumeHead + 1, finishPos), start + #resumeHead + 1)
                local resume = parseResume(result)
                if resume then
                    if comments then
                        resume.comment = table.concat(comments, '\n')
                    else
                        resume.comment = text:match('%s*#?%s*(.+)', resume.finish - start)
                    end
                    result.types[#result.types + 1] = resume
                    result.finish = resume.finish
                end
                comments = nil
                return true
            else
                comments = comments or {}
                comments[#comments + 1] = text:sub(2)
            end
        end
        return false
    end

    while pushResume() do
    end

    lockResume = false
end

--- @return parser.object.doc.type?
function parseType(parent)
    --- @type parser.object.doc.type
    local result = {
        type = 'doc.type',
        parent = parent,
        types = {},
        firstFinish = 0, -- suppress warning
    }

    while true do
        local typeUnit = parseTypeUnit(result)
        if not typeUnit then
            break
        end

        result.types[#result.types + 1] = typeUnit
        if not result.start then
            result.start = typeUnit.start
        end

        if not checkToken('symbol', '|', 1) then
            break
        end
        nextToken()
    end

    result.start = result.start or getFinish()

    if checkToken('symbol', '?', 1) then
        nextToken()
        result.optional = true
    end
    result.finish = getFinish()
    result.firstFinish = result.finish

    doResume(result)

    if #result.types == 0 then
        pushWarning({
            type = 'LUADOC_MISS_TYPE_NAME',
            start = getFinish(),
            finish = getFinish(),
        })
        return
    end
    return result
end

local function initObj(ty)
    return {
        type = ty,
        start = getFinish(),
        finish = getFinish(),
    }
end

--- @type table<string,fun(doc:string):parser.object.doc?, parser.object.doc.type[]?>
local docSwitch = {
    ['class'] = function()
        --- @type parser.object.doc.class
        local result = {
            type = 'doc.class',
            fields = {},
            operators = {},
            calls = {},
        }
        result.docAttr = parseDocAttr(result)
        result.class = parseClassName(result)
        if not result.class then
            pushWarning({
                type = 'LUADOC_MISS_CLASS_NAME',
                start = getFinish(),
                finish = getFinish(),
            })
            return
        end
        result.start = getStart()
        result.finish = getFinish()
        result.signs = parseSigns(result)
        if not checkToken('symbol', ':', 1) then
            return result
        end
        nextToken()

        result.extends = {}

        while true do
            local extend = parseExtendsName(result)
                or parseTable(result)
                or parseTuple(result)

            if not extend then
                pushWarning({
                    type = 'LUADOC_MISS_CLASS_EXTENDS_NAME',
                    start = getFinish(),
                    finish = getFinish(),
                })
                return result
            end
            result.extends[#result.extends + 1] = extend
            result.finish = getFinish()
            if not checkToken('symbol', ',', 1) then
                break
            end
            nextToken()
        end
        return result
    end,

    ['type'] = function()
        local first = parseType()
        if not first then
            return
        end
        local rests
        while checkToken('symbol', ',', 1) do
            nextToken()
            local rest = parseType()
            if not rests then
                rests = {}
            end
            rests[#rests + 1] = rest
        end
        return first, rests
    end,

    ['alias'] = function()
        --- @type parser.object.doc.alias
        local result = {
            type = 'doc.alias',
        }
        result.docAttr = parseDocAttr(result)
        result.alias = parseAliasName(result)
        if not result.alias then
            pushWarning({
                type = 'LUADOC_MISS_ALIAS_NAME',
                start = getFinish(),
                finish = getFinish(),
            })
            return
        end
        result.start = getStart()
        result.signs = parseSigns(result)
        result.extends = parseType(result)
        if not result.extends then
            pushWarning({
                type = 'LUADOC_MISS_ALIAS_EXTENDS',
                start = getFinish(),
                finish = getFinish(),
            })
            return
        end
        result.finish = getFinish()
        return result
    end,

    ['param'] = function()
        --- @type parser.object.doc.param
        local result = {
            type = 'doc.param',
        }
        result.param = parseParamName(result)
        if not result.param then
            pushWarning({
                type = 'LUADOC_MISS_PARAM_NAME',
                start = getFinish(),
                finish = getFinish(),
            })
            return
        end
        if checkToken('symbol', '?', 1) then
            nextToken()
            result.optional = true
        end
        result.start = result.param.start
        result.finish = getFinish()
        result.extends = parseType(result)
        if not result.extends then
            pushWarning({
                type = 'LUADOC_MISS_PARAM_EXTENDS',
                start = getFinish(),
                finish = getFinish(),
            })
            return result
        end
        result.finish = getFinish()
        result.firstFinish = result.extends.firstFinish
        return result
    end,

    ['return'] = function()
        --- @type parser.object.doc.return
        local result = {
            type = 'doc.return',
            returns = {},
        }
        while true do
            local dots = parseDots('doc.return.name')
            if dots then
                Ci = Ci - 1
            end
            local docType = parseType(result)
            if not docType then
                break
            end
            if not result.start then
                result.start = docType.start
            end
            if checkToken('symbol', '?', 1) then
                nextToken()
                docType.optional = true
            end
            if dots then
                docType.name = dots
                dots.parent = docType
            else
                docType.name = parseReturnName(docType)
            end
            result.returns[#result.returns + 1] = docType
            if not checkToken('symbol', ',', 1) then
                break
            end
            nextToken()
        end
        if #result.returns == 0 then
            return
        end
        result.finish = getFinish()
        return result
    end,

    ['field'] = function()
        --- @type parser.object.doc.field
        local result = {
            type = 'doc.field',
        }
        try(function()
            local tp, value = nextToken()
            if tp == 'name' then
                if
                    value == 'public'
                    or value == 'protected'
                    or value == 'private'
                    or value == 'package'
                then
                    local tp2 = peekToken(1)
                    local tp3 = peekToken(2)
                    if tp2 == 'name' and not tp3 then
                        return false
                    end
                    result.visible = value
                    result.start = getStart()
                    return true
                end
            end
            return false
        end)
        --- @type parser.object.doc.field.name|parser.object.doc.type?
        result.field = parseName('doc.field.name', result) or parseIndexField(result)
        if not result.field then
            pushWarning({
                type = 'LUADOC_MISS_FIELD_NAME',
                start = getFinish(),
                finish = getFinish(),
            })
            return
        end
        if not result.start then
            result.start = result.field.start
        end
        if checkToken('symbol', '?', 1) then
            nextToken()
            result.optional = true
        end
        result.extends = parseType(result)
        if not result.extends then
            pushWarning({
                type = 'LUADOC_MISS_FIELD_EXTENDS',
                start = getFinish(),
                finish = getFinish(),
            })
            return
        end
        result.finish = getFinish()
        return result
    end,

    ['generic'] = function()
        --- @type parser.object.doc.generic
        local result = {
            type = 'doc.generic',
            generics = {},
        }
        while true do
            local object = {
                type = 'doc.generic.object',
                parent = result,
            }
            object.generic = parseName('doc.generic.name', object)
            if not object.generic then
                pushWarning({
                    type = 'LUADOC_MISS_GENERIC_NAME',
                    start = getFinish(),
                    finish = getFinish(),
                })
                return
            end
            object.start = object.generic.start
            result.start = result.start or object.start
            if checkToken('symbol', ':', 1) then
                nextToken()
                object.extends = parseType(object)
            end
            object.finish = getFinish()
            result.generics[#result.generics + 1] = object
            if not checkToken('symbol', ',', 1) then
                break
            end
            nextToken()
        end
        result.finish = getFinish()
        return result
    end,

    ['vararg'] = function()
        --- @type parser.object.doc.vararg
        local result = {
            type = 'doc.vararg',
        }
        result.vararg = parseType(result)
        if not result.vararg then
            pushWarning({
                type = 'LUADOC_MISS_VARARG_TYPE',
                start = getFinish(),
                finish = getFinish(),
            })
            return
        end
        result.start = result.vararg.start
        result.finish = result.vararg.finish
        return result
    end,

    ['overload'] = function()
        local tp, name = peekToken()
        if tp ~= 'name' or (name ~= 'fun' and name ~= 'async') then
            pushWarning({
                type = 'LUADOC_MISS_FUN_AFTER_OVERLOAD',
                start = getFinish(),
                finish = getFinish(),
            })
            return
        end
        --- @type parser.object.doc.overload
        local result = {
            type = 'doc.overload',
        }
        result.overload = parseFunction(result)
        if not result.overload then
            return
        end
        result.overload.parent = result
        result.start = result.overload.start
        result.finish = result.overload.finish
        return result
    end,

    ['deprecated'] = function()
        --- @type parser.object.doc.deprecated
        return initObj('doc.deprecated')
    end,

    ['meta'] = function()
        --- @type parser.object.doc.meta
        local meta = initObj('doc.meta')
        meta.name = parseMetaName(meta)
        return meta
    end,

    ['version'] = function()
        --- @type parser.object.doc.version
        local result = {
            type = 'doc.version',
            versions = {},
        }
        while true do
            local tp, text = nextToken()
            if not tp then
                pushWarning({
                    type = 'LUADOC_MISS_VERSION',
                    start = getFinish(),
                    finish = getFinish(),
                })
                break
            end
            if not result.start then
                result.start = getStart()
            end
            --- @type parser.object.doc.version.unit
            local version = {
                type = 'doc.version.unit',
                parent = result,
                start = getStart(),
            }
            if tp == 'symbol' then
                if text == '>' then
                    version.ge = true
                elseif text == '<' then
                    version.le = true
                end
                tp, text = nextToken()
            end
            if tp ~= 'name' then
                pushWarning({
                    type = 'LUADOC_MISS_VERSION',
                    start = getStart(),
                    finish = getFinish(),
                })
                break
            end
            version.version = tonumber(text) or text
            version.finish = getFinish()
            result.versions[#result.versions + 1] = version
            if not checkToken('symbol', ',', 1) then
                break
            end
            nextToken()
        end
        if #result.versions == 0 then
            return
        end
        result.finish = getFinish()
        return result
    end,

    ['see'] = function()
        --- @type parser.object.doc.see
        local result = {
            type = 'doc.see',
        }
        result.name = parseSeeName(result)
        if not result.name then
            pushWarning({
                type = 'LUADOC_MISS_SEE_NAME',
                start = getFinish(),
                finish = getFinish(),
            })
            return
        end
        result.start = result.name.start
        result.finish = result.name.finish
        return result
    end,

    ['diagnostic'] = function()
        --- @type parser.object.doc.diagnostic
        local result = {
            type = 'doc.diagnostic',
        }
        local nextTP, mode = nextToken()
        if nextTP ~= 'name' then
            pushWarning({
                type = 'LUADOC_MISS_DIAG_MODE',
                start = getFinish(),
                finish = getFinish(),
            })
            return
        end
        result.mode = mode
        result.start = getStart()
        result.finish = getFinish()
        if
            mode ~= 'disable-next-line'
            and mode ~= 'disable-line'
            and mode ~= 'disable'
            and mode ~= 'enable'
        then
            pushWarning({
                type = 'LUADOC_ERROR_DIAG_MODE',
                start = result.start,
                finish = result.finish,
            })
        end

        if checkToken('symbol', ':', 1) then
            nextToken()
            result.names = {}
            while true do
                local name = parseName('doc.diagnostic.name', result)
                if not name then
                    pushWarning({
                        type = 'LUADOC_MISS_DIAG_NAME',
                        start = getFinish(),
                        finish = getFinish(),
                    })
                    return result
                end
                result.names[#result.names + 1] = name
                if not checkToken('symbol', ',', 1) then
                    break
                end
                nextToken()
            end
        end

        result.finish = getFinish()

        return result
    end,

    ['module'] = function()
        --- @type parser.object.doc.module
        local result = initObj('doc.module')
        local tp, content = peekToken()
        if tp == 'string' then
            result.module = content
            nextToken()
            result.start = getStart()
            result.finish = getFinish()
            result.smark = getMark()
        else
            pushWarning({
                type = 'LUADOC_MISS_MODULE_NAME',
                start = getFinish(),
                finish = getFinish(),
            })
        end
        return result
    end,

    ['async'] = function()
        --- @type parser.object.doc.async
        return initObj('doc.async')
    end,

    ['nodiscard'] = function()
        --- @type parser.object.doc.nodiscard
        return initObj('doc.nodiscard')
    end,

    ['as'] = function()
        --- @type parser.object.doc.as
        local result = initObj('doc.as')
        result.as = parseType(result)
        result.finish = getFinish()
        return result
    end,

    ['cast'] = function()
        --- @type parser.object.doc.cast
        local result = initObj('doc.cast')
        result.casts = {}
        --- @type parser.object.doc.cast.name?
        local loc = parseName('doc.cast.name', result)
        if not loc then
            pushWarning({
                type = 'LUADOC_MISS_LOCAL_NAME',
                start = getFinish(),
                finish = getFinish(),
            })
            return result
        end

        result.name = loc
        result.finish = loc.finish

        while true do
            local block = {
                type = 'doc.cast.block',
                parent = result,
                start = getFinish(),
                finish = getFinish(),
            }
            if checkToken('symbol', '+', 1) then
                block.mode = '+'
                nextToken()
                block.start = getStart()
                block.finish = getFinish()
            elseif checkToken('symbol', '-', 1) then
                block.mode = '-'
                nextToken()
                block.start = getStart()
                block.finish = getFinish()
            end

            if checkToken('symbol', '?', 1) then
                block.optional = true
                nextToken()
                block.finish = getFinish()
            else
                block.extends = parseType(block)
                if block.extends then
                    block.start = block.start or block.extends.start
                    block.finish = block.extends.finish
                end
            end

            if block.optional or block.extends then
                result.casts[#result.casts + 1] = block
            end
            result.finish = block.finish

            if checkToken('symbol', ',', 1) then
                nextToken()
            else
                break
            end
        end

        return result
    end,

    ['operator'] = function()
        --- @type parser.object.doc.operator
        local result = initObj('doc.operator')

        --- @type parser.object.doc.operator.name?
        local op = parseName('doc.operator.name', result)
        if not op then
            pushWarning({
                type = 'LUADOC_MISS_OPERATOR_NAME',
                start = getFinish(),
                finish = getFinish(),
            })
            return
        end
        result.op = op
        result.finish = op.finish

        if checkToken('symbol', '(', 1) then
            nextToken()
            if checkToken('symbol', ')', 1) then
                nextToken()
            else
                local exp = parseType(result)
                if exp then
                    result.exp = exp
                    result.finish = exp.finish
                end
                nextSymbolOrError(')')
            end
        end

        nextSymbolOrError(':')

        local ret = parseType(result)
        if ret then
            result.extends = ret
            result.finish = ret.finish
        end

        return result
    end,

    ['source'] = function(doc)
        local fullSource = doc:sub(#'source' + 1)
        if not fullSource or fullSource == '' then
            return
        end
        fullSource = util.trim(fullSource)
        if fullSource == '' then
            return
        end
        local source, line, char = fullSource:match('^(.-):?(%d*):?(%d*)$')
        source = source or fullSource
        line = tonumber(line) or 1
        char = tonumber(char) or 0
        --- @type parser.object.doc.source
        local result = {
            type = 'doc.source',
            start = getStart(),
            finish = getFinish(),
            path = source,
            line = line,
            char = char,
        }
        return result
    end,

    ['enum'] = function()
        local attr = parseDocAttr()
        local name = parseName('doc.enum.name') --[[@as parser.object.doc.enum.name]]
        if not name then
            return
        end
        --- @type parser.object.doc.enum
        local result = {
            type = 'doc.enum',
            start = name.start,
            finish = name.finish,
            enum = name,
            docAttr = attr,
        }
        name.parent = result
        if attr then
            attr.parent = result
        end
        return result
    end,

    ['private'] = function()
        --- @type parser.object.doc.private
        return initObj('doc.private')
    end,

    ['protected'] = function()
        --- @type parser.object.doc.protected
        return initObj('doc.protected')
    end,

    ['public'] = function()
        --- @type parser.object.doc.public
        return initObj('doc.public')
    end,

    ['package'] = function()
        --- @type parser.object.doc.package
        return initObj('doc.package')
    end,
}

--- @return parser.object.doc?
--- @return parser.object.doc.type[]?
local function convertTokens(doc)
    local tp, text = nextToken()
    if not tp then
        return
    end
    if tp ~= 'name' then
        pushWarning({
            type = 'LUADOC_MISS_CATE_NAME',
            start = getStart(),
            finish = getFinish(),
        })
        return
    end
    if docSwitch[text] then
        return docSwitch[text](doc)
    end
end

--- @param text string
--- @return string
local function trimTailComment(text)
    local comment = text
    if text:sub(1, 1) == '@' then
        comment = util.trim(text:sub(2))
    elseif text:sub(1, 1) == '#' then
        comment = util.trim(text:sub(2))
    elseif text:sub(1, 2) == '--' then
        comment = util.trim(text:sub(3))
    end
    if comment:find('^%s*[\'"[]') and comment:find('[\'"%]]%s*$') then
        local state = compile(comment:gsub('^%s+', ''), 'String')
        if state and state.ast then
            comment = state.ast[1] --[[@as string]]
        end
    end
    return util.trim(comment)
end

--- @param comment parser.object.comment
--- @return parser.object.doc
--- @return parser.object.doc.type[]?
local function buildLuaDoc(comment)
    local text = comment.text
    local startPos = (comment.type == 'comment.short' and text:match('^%-%s*@()'))
        or (comment.type == 'comment.long' and text:match('^@()'))
    if not startPos then
        --- @type parser.object.doc.comment
        return {
            type = 'doc.comment',
            start = comment.start,
            finish = comment.finish,
            range = comment.finish,
            comment = comment,
        }
    end
    local startOffset = comment.start
    if comment.type == 'comment.long' then
        startOffset = startOffset + #comment.mark - 2
    end

    local doc = text:sub(startPos)

    parseTokens(doc, startOffset + startPos)
    local result, rests = convertTokens(doc)
    if result then
        result.range = math.max(comment.finish, result.finish)
        local finish = result.firstFinish or result.finish
        if rests then
            for _, rest in ipairs(rests) do
                rest.range = comment.finish
                finish = rest.firstFinish or result.finish
            end
        end
        local cstart = text:find('%S', finish - comment.start)
        if cstart and cstart < comment.finish then
            --- @type parser.object.doc.tailcomment
            result.comment = {
                type = 'doc.tailcomment',
                start = cstart + comment.start,
                finish = comment.finish,
                parent = result,
                text = trimTailComment(text:sub(cstart)),
            }
            if rests then
                for _, rest in ipairs(rests) do
                    rest.comment = result.comment
                end
            end
        end
    end

    if result then
        return result, rests
    end

    return {
        type = 'doc.comment',
        start = comment.start,
        finish = comment.finish,
        range = comment.finish,
        comment = comment,
    }
end

local function isTailComment(text, doc)
    if not doc then
        return false
    end
    local left = doc.originalComment.start
    local row, col = guide.rowColOf(left)
    local lineStart = Lines[row] or 0
    local hasCodeBefore = text:sub(lineStart, lineStart + col):find('[%w_]')
    return hasCodeBefore
end

local function isContinuedDoc(lastDoc, nextDoc)
    if not nextDoc then
        return false
    end
    if nextDoc.type == 'doc.diagnostic' then
        return true
    end
    if lastDoc.type == 'doc.type' or lastDoc.type == 'doc.module' or lastDoc.type == 'doc.enum' then
        if nextDoc.type ~= 'doc.comment' then
            return false
        end
    elseif
        lastDoc.type == 'doc.class'
        or lastDoc.type == 'doc.field'
        or lastDoc.type == 'doc.operator'
    then
        if
            nextDoc.type ~= 'doc.field'
            and nextDoc.type ~= 'doc.operator'
            and nextDoc.type ~= 'doc.comment'
            and nextDoc.type ~= 'doc.overload'
            and nextDoc.type ~= 'doc.source'
        then
            return false
        end
    end
    if nextDoc.type == 'doc.cast' then
        return false
    end
    return true
end

local function isNextLine(lastDoc, nextDoc)
    if not nextDoc then
        return false
    end
    local lastRow = guide.rowColOf(lastDoc.finish)
    local newRow = guide.rowColOf(nextDoc.start)
    return newRow - lastRow == 1
end

local function bindGeneric(binded)
    local generics = {} --- @type table<string,parser.object.doc.generic.object>
    for _, doc in ipairs(binded) do
        if doc.type == 'doc.generic' then
            for _, obj in ipairs(doc.generics) do
                local name = obj.generic[1]
                generics[name] = obj
            end
        elseif doc.type == 'doc.class' or doc.type == 'doc.alias' then
            for _, sign in ipairs(doc.signs or {}) do
                local name = sign[1]
                generics[name] = sign
            end
        end

        if
            doc.type == 'doc.param'
            or doc.type == 'doc.vararg'
            or doc.type == 'doc.return'
            or doc.type == 'doc.type'
            or doc.type == 'doc.class'
            or doc.type == 'doc.alias'
        then
            --- @param src parser.object.doc.type.name
            guide.eachSourceType(doc, 'doc.type.name', function(src)
                local name = src[1]
                if generics[name] then
                    local g = src --[[@as parser.object.doc.generic.name]]
                    g.type = 'doc.generic.name'
                    g.generic = generics[name]
                end
            end)
            --- @param src parser.object.doc.type.code
            guide.eachSourceType(doc, 'doc.type.code', function(src)
                local name = src[1]
                if generics[name] then
                    local c = src --[[@as parser.object.doc.generic.name]]
                    c.type = 'doc.generic.name'
                    c.literal = true
                end
            end)
        end
    end
end

local function bindDocWithSource(doc, source)
    if not source.bindDocs then
        source.bindDocs = {}
    end
    if source.bindDocs[#source.bindDocs] ~= doc then
        source.bindDocs[#source.bindDocs + 1] = doc
    end
    doc.bindSource = source
end

local function bindDoc(source, binded)
    local isParam = source.type == 'self'
        or source.type == 'local'
            and (source.parent.type == 'funcargs' or (source.parent.type == 'in' and source.finish <= source.parent.keys.finish))
    local ok = false
    for _, doc in ipairs(binded) do
        if not doc.bindSource then
            if
                doc.type == 'doc.class'
                or doc.type == 'doc.deprecated'
                or doc.type == 'doc.version'
                or doc.type == 'doc.module'
                or doc.type == 'doc.source'
                or doc.type == 'doc.private'
                or doc.type == 'doc.protected'
                or doc.type == 'doc.public'
                or doc.type == 'doc.package'
                or doc.type == 'doc.see'
            then
                if source.type == 'function' or isParam then
                -- pass
                else
                    bindDocWithSource(doc, source)
                    ok = true
                end
            elseif doc.type == 'doc.type' then
                if source.type == 'function' or isParam or source._bindedDocType then
                --pass
                else
                    source._bindedDocType = true
                    bindDocWithSource(doc, source)
                    ok = true
                end
            elseif doc.type == 'doc.overload' then
                source.bindDocs = source.bindDocs or {}
                source.bindDocs[#source.bindDocs + 1] = doc
                if source.type == 'function' then
                    bindDocWithSource(doc, source)
                end
                ok = true
            elseif doc.type == 'doc.param' then
                if isParam and doc.param[1] == source[1] then
                    bindDocWithSource(doc, source)
                    ok = true
                elseif source.type == '...' and doc.param[1] == '...' then
                    bindDocWithSource(doc, source)
                    ok = true
                elseif source.type == 'self' and doc.param[1] == 'self' then
                    bindDocWithSource(doc, source)
                    ok = true
                elseif source.type == 'function' then
                    if not source.bindDocs then
                        source.bindDocs = {}
                    end
                    source.bindDocs[#source.bindDocs + 1] = doc
                    if source.args then
                        for _, arg in ipairs(source.args) do
                            if arg[1] == doc.param[1] then
                                bindDocWithSource(doc, arg)
                                break
                            end
                        end
                    end
                end
            elseif doc.type == 'doc.vararg' then
                if source.type == '...' then
                    bindDocWithSource(doc, source)
                    ok = true
                end
            elseif
                doc.type == 'doc.return'
                or doc.type == 'doc.generic'
                or doc.type == 'doc.async'
                or doc.type == 'doc.nodiscard'
            then
                if source.type == 'function' then
                    bindDocWithSource(doc, source)
                    ok = true
                end
            elseif doc.type == 'doc.enum' then
                if source.type == 'table' then
                    bindDocWithSource(doc, source)
                    ok = true
                end
                if source.value and source.value.type == 'table' then
                    bindDocWithSource(doc, source.value)
                end
            elseif doc.type == 'doc.comment' then
                bindDocWithSource(doc, source)
                ok = true
            end
        end
    end
    return ok
end

--- @param sources parser.bindDocAccept[]
local function bindDocsBetween(sources, binded, start, finish)
    -- Find the first one using bisection method
    local max = #sources
    local index
    local left = 1
    local right = max
    for _ = 1, 1000 do
        index = left + (right - left) // 2
        if index <= left then
            index = left
            break
        elseif index >= right then
            index = right
            break
        end
        local src = sources[index]
        if src.start < start then
            left = index + 1
        else
            right = index
        end
    end

    local ok = false
    -- Binding from front to back
    for i = index, max do
        local src = sources[i]
        if src and src.start >= start then
            if src.start >= finish then
                break
            end
            if src.start >= start then
                if
                    src.type == 'local'
                    or src.type == 'self'
                    or src.type == 'setlocal'
                    or src.type == 'setglobal'
                    or src.type == 'tablefield'
                    or src.type == 'tableindex'
                    or src.type == 'setfield'
                    or src.type == 'setindex'
                    or src.type == 'setmethod'
                    or src.type == 'function'
                    or src.type == 'return'
                    or src.type == '...'
                then
                    if bindDoc(src, binded) then
                        ok = true
                    end
                end
            end
        end
    end

    return ok
end

local function bindReturnIndex(binded)
    local returnIndex = 0
    for _, doc in ipairs(binded) do
        if doc.type == 'doc.return' then
            for _, rtn in ipairs(doc.returns) do
                returnIndex = returnIndex + 1
                rtn.returnIndex = returnIndex
            end
        end
    end
end

local function bindCommentsToDoc(doc, comments)
    doc.bindComments = comments
    for _, comment in ipairs(comments) do
        comment.bindSource = doc
    end
end

local function bindCommentsAndFields(binded)
    local class
    local comments = {}
    local source
    for _, doc in ipairs(binded) do
        local clear_source = true
        if doc.type == 'doc.class' then
            -- Multiple classes are written together continuously,
            -- and only the last class can be bound to source.
            if class then
                class.bindSource = nil
            end
            if source then
                doc.source = source
                source.bindSource = doc
            end
            class = doc
            bindCommentsToDoc(doc, comments)
            comments = {}
        elseif doc.type == 'doc.field' then
            if class then
                class.fields[#class.fields + 1] = doc
                doc.class = class
            end
            if source then
                doc.source = source
                source.bindSource = doc
            end
            bindCommentsToDoc(doc, comments)
            comments = {}
        elseif doc.type == 'doc.operator' then
            if class then
                class.operators[#class.operators + 1] = doc
                doc.class = class
            end
            bindCommentsToDoc(doc, comments)
            comments = {}
        elseif doc.type == 'doc.overload' then
            if class then
                class.calls[#class.calls + 1] = doc
                doc.class = class
            end
        elseif doc.type == 'doc.alias' or doc.type == 'doc.enum' then
            bindCommentsToDoc(doc, comments)
            comments = {}
        elseif doc.type == 'doc.comment' then
            comments[#comments + 1] = doc
        elseif doc.type == 'doc.source' then
            source = doc
            clear_source = false
        end
        if clear_source then
            source = nil
        end
    end
end

--- @param sources parser.bindDocAccept[]
--- @param binded? parser.object.doc[]
local function bindDocWithSources(sources, binded)
    if not binded then
        return
    end
    local lastDoc = binded[#binded]
    if not lastDoc then
        return
    end
    for _, doc in ipairs(binded) do
        doc.bindGroup = binded
    end
    bindGeneric(binded)
    bindCommentsAndFields(binded)
    bindReturnIndex(binded)

    -- doc is special node
    if lastDoc.special then
        if bindDoc(lastDoc.special, binded) then
            return
        end
    end

    local row = guide.rowColOf(lastDoc.finish)
    local suc = bindDocsBetween(sources, binded, guide.positionOf(row, 0), lastDoc.start)
    if not suc then
        bindDocsBetween(sources, binded, guide.positionOf(row + 1, 0), guide.positionOf(row + 2, 0))
    end
end

local bindDocAccept = {
    'local',
    'setlocal',
    'setglobal',
    'setfield',
    'setmethod',
    'setindex',
    'tablefield',
    'tableindex',
    'self',
    'function',
    'return',
    '...',
}

--- @alias parser.bindDocAccept
--- | parser.object.local
--- | parser.object.setlocal
--- | parser.object.setglobal
--- | parser.object.setfield
--- | parser.object.setmethod
--- | parser.object.setindex
--- | parser.object.tablefield
--- | parser.object.tableindex
--- | parser.object.self
--- | parser.object.function
--- | parser.object.return
--- | parser.object.vararg

--- @param state parser.state
local function bindDocs(state)
    local text = state.lua
    --- @type parser.bindDocAccept[]
    local sources = {}
    --- @param src parser.bindDocAccept
    guide.eachSourceTypes(state.ast, bindDocAccept, function(src)
        sources[#sources + 1] = src
    end)
    table.sort(sources, function(a, b)
        return a.start < b.start
    end)
    local binded
    for i, doc in ipairs(state.ast.docs) do
        if not binded then
            binded = {}
            state.ast.docs.groups[#state.ast.docs.groups + 1] = binded
        end
        binded[#binded + 1] = doc
        if doc.specialBindGroup then
            bindDocWithSources(sources, doc.specialBindGroup)
            binded = nil
        elseif isTailComment(text, doc) and doc.type ~= 'doc.class' and doc.type ~= 'doc.field' then
            bindDocWithSources(sources, binded)
            binded = nil
        else
            local nextDoc = state.ast.docs[i + 1]
            if nextDoc and nextDoc.special or not isNextLine(doc, nextDoc) then
                bindDocWithSources(sources, binded)
                binded = nil
            end
            if not isContinuedDoc(doc, nextDoc) and not isTailComment(text, nextDoc) then
                bindDocWithSources(sources, binded)
                binded = nil
            end
        end
    end
end

--- @param state parser.state
local function findTouch(state, doc)
    local text = assert(state.lua)
    local pos = guide.positionToOffset(state, doc.originalComment.start)
    for i = pos - 2, 1, -1 do
        local c = text:sub(i, i)
        if c == '\r' or c == '\n' then
            break
        elseif c ~= ' ' and c ~= '\t' then
            doc.touch = guide.offsetToPosition(state, i)
            break
        end
    end
end

--- @param state parser.state
local function luadoc(state)
    local ast = assert(state.ast)
    local comments = state.comms
    table.sort(comments, function(a, b)
        return a.start < b.start
    end)
    ast.docs = {
        type = 'doc',
        parent = ast,
        groups = {},
    }

    pushWarning = function(err)
        local errs = state.errs
        if err.finish < err.start then
            err.finish = err.start
        end
        local last = errs[#errs]
        if last then
            if last.start <= err.start and last.finish >= err.finish then
                return
            end
        end
        err.level = err.level or 'Warning'
        errs[#errs + 1] = err
        return err
    end
    Lines = state.lines

    local ci = 1
    NextComment = function(offset, peek)
        local comment = comments[ci + (offset or 0)]
        if not peek then
            ci = ci + 1 + (offset or 0)
        end
        return comment
    end

    local function insertDoc(doc, comment)
        ast.docs[#ast.docs + 1] = doc
        doc.parent = ast.docs
        if ast.start > doc.start then
            ast.start = doc.start
        end
        if ast.finish < doc.finish then
            ast.finish = doc.finish
        end
        doc.originalComment = comment
        if comment.type == 'comment.long' then
            findTouch(state, doc)
        end
    end

    while true do
        local comment = NextComment()
        if not comment then
            break
        end
        lockResume = false
        local doc, rests = buildLuaDoc(comment)
        if doc then
            insertDoc(doc, comment)
            for _, rest in ipairs(rests or {}) do
                insertDoc(rest, comment)
            end
        end
    end

   if ast.state.pluginDocs then
        for _, doc in ipairs(ast.state.pluginDocs) do
            insertDoc(doc, doc.originalComment)
        end
        ---@param a unknown
        ---@param b unknown
        table.sort(ast.docs, function(a, b)
            return a.start < b.start
        end)
        ast.state.pluginDocs = nil
    end

    ast.docs.start = ast.start
    ast.docs.finish = ast.finish

    if #ast.docs == 0 then
        return
    end

    bindDocs(state)
end

return {
    --- @param src parser.object
    --- @param comment parser.object.comment.short
    --- @param group? parser.object.comment.short
    buildAndBindDoc = function(ast, src, comment, group)
        local doc = buildLuaDoc(comment)
        if doc then
            local pluginDocs = ast.state.pluginDocs or {}
            pluginDocs[#pluginDocs + 1] = doc
            doc.special = src
            doc.originalComment = comment
            doc.virtual = true
            doc.specialBindGroup = group
            ast.state.pluginDocs = pluginDocs
            return doc
        end
    end,
    luadoc = luadoc,
}
