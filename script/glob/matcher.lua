local m = require('lpeglabel')

local Slash = m.S('/\\') ^ 1
local Symbol = m.S(',{}[]*?/\\')
local Char = 1 - Symbol
local Path = (1 - m.S([[\/*?"<>|]])) ^ 1 * Slash
local NoWord = #(m.P(-1) + Symbol)

local Marcher = {}
Marcher.__index = Marcher
Marcher.__name = 'matcher'

function Marcher:exp(state, index)
    local exp = state[index]
    if not exp then
        return
    end
    if exp.type == 'word' then
        return self:word(exp, state, index + 1)
    elseif exp.type == 'char' then
        return self:char(exp, state, index + 1)
    elseif exp.type == '**' then
        return self:anyPath(exp, state, index + 1)
    elseif exp.type == '*' then
        return self:anyChar(exp, state, index + 1)
    elseif exp.type == '?' then
        return self:oneChar(exp, state, index + 1)
    elseif exp.type == '[]' then
        return self:range(exp, state, index + 1)
    elseif exp.type == '/' then
        return self:slash(exp, state, index + 1)
    end
end

function Marcher:word(exp, state, index)
    local current = self:exp(exp.value, 1)
    local after = self:exp(state, index)
    if after then
        return current * Slash * after
    else
        return current
    end
end

function Marcher:char(exp, state, index)
    local current = m.P(exp.value)
    local after = self:exp(state, index)
    if after then
        return current * after * NoWord
    else
        return current * NoWord
    end
end

function Marcher:anyPath(_, state, index)
    local after = self:exp(state, index)
    if after then
        return m.P({
            'Main',
            Main = after + Path * m.V('Main'),
        })
    else
        return Path ^ 0
    end
end

function Marcher:anyChar(_, state, index)
    local after = self:exp(state, index)
    if after then
        return m.P({
            'Main',
            Main = after + Char * m.V('Main'),
        })
    else
        return Char ^ 0
    end
end

function Marcher:oneChar(_, state, index)
    local after = self:exp(state, index)
    if after then
        return Char * after
    else
        return Char
    end
end

function Marcher:range(exp, state, index)
    local after = self:exp(state, index)
    local ranges = {}
    local selects = {}
    for _, range in ipairs(exp.value) do
        if #range == 1 then
            selects[#selects + 1] = range[1]
        elseif #range == 2 then
            ranges[#ranges + 1] = range[1] .. range[2]
        end
    end
    local current = m.S(table.concat(selects)) + m.R(table.unpack(ranges))
    if after then
        return current * after
    else
        return current
    end
end

function Marcher:slash(_, state, index)
    local after = self:exp(state, index)
    if after then
        return after
    else
        self.needDirectory = true
        return nil
    end
end

function Marcher:pattern(state)
    if state.root then
        local after = self:exp(state, 1)
        if after then
            return m.C(after)
        else
            return nil
        end
    else
        return m.C(self:anyPath(nil, state, 1))
    end
end

function Marcher:isNeedDirectory()
    return self.needDirectory == true
end

function Marcher:isNegative()
    return self.state.neg == true
end

function Marcher:__call(path)
    return self.matcher:match(path)
end

return function(state, options)
    local self = setmetatable({
        options = options,
        state = state,
    }, Marcher)
    self.matcher = self:pattern(state)
    if not self.matcher then
        return nil
    end
    return self
end
