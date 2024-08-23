local lpeg = require('lpeglabel')
local P, S, R = lpeg.P, lpeg.S, lpeg.R

local sp = S(' \t\v\f')

local nl = P('\r\n') + S('\r\n')

local number = R('09') ^ 1

local word = R('AZ', 'az', '__', '\x80\xff') * R('AZ', 'az', '09', '__', '\x80\xff') ^ 0

local symbol = P('==')
    + P('~=')
    + P('--')
    -- non-standard:
    + P('<<=')
    + P('>>=')
    + P('//=')
    -- end non-standard
    + P('<<')
    + P('>>')
    + P('<=')
    + P('>=')
    + P('//')
    + P('...')
    + P('..')
    + P('::')
    -- non-standard:
    + P('!=')
    + P('&&')
    + P('||')
    + P('/*')
    + P('*/')
    + P('+=')
    + P('-=')
    + P('*=')
    + P('%=')
    + P('&=')
    + P('|=')
    + P('^=')
    + P('/=')
    -- end non-standard
    -- singles
    + S('+-*/!#%^&()={}[]|\\\'":;<>,.?~`')

local unknown = (1 - number - word - symbol - sp - nl) ^ 1

local token = lpeg.Cp() * lpeg.C(nl + number + word + symbol + unknown)

local parser = lpeg.Ct((sp ^ 1 + token) ^ 0)

--- Parse a string of Lua code into a table of tokens.
--- @param lua string
--- @return integer[]
return function(lua)
    return parser:match(lua)
end
