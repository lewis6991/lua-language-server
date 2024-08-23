local suc, codeFormat = pcall(require, 'code_format')
if not suc then
    return
end

local fs = require('bee.filesystem')
local config = require('config')
local pformatting = require('provider.formatting')

local M = {}

function M.loadDictionaryFromFile(filePath)
    return codeFormat.spell_load_dictionary_from_path(filePath)
end

function M.loadDictionaryFromBuffer(buffer)
    return codeFormat.spell_load_dictionary_from_buffer(buffer)
end

function M.addWord(word)
    return codeFormat.spell_load_dictionary_from_buffer(word)
end

function M.spellCheck(uri, text)
    if not M._dictionaryLoaded then
        M.initDictionary()
        M._dictionaryLoaded = true
    end

    local tempDict = config.get(uri, 'Lua.spell.dict')

    return codeFormat.spell_analysis(uri, text, tempDict)
end

function M.getSpellSuggest(word)
    local status, result = codeFormat.spell_suggest(word)
    if status then
        return result
    end
end

function M.initDictionary()
    local basicDictionary = fs.path(METAPATH) / 'spell/dictionary.txt'
    local luaDictionary = fs.path(METAPATH) / 'spell/lua_dict.txt'

    M.loadDictionaryFromFile(basicDictionary:string())
    M.loadDictionaryFromFile(luaDictionary:string())
    pformatting.updateNonStandardSymbols(config.get(nil, 'Lua.runtime.nonstandardSymbol'))
end

return M
