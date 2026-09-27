-- Índice de trigramas (ADR-05): gera candidatos fuzzy sem comparar a
-- consulta contra todo o vocabulário. Construído ao fim do IndexBuilder
-- sobre o vocabulário, as `phrases` (chave com espaço) e os termos de alias.
local NS = SmartShopSearch
local TrigramIndex = {}
TrigramIndex.__index = TrigramIndex

local MAX_CANDIDATES = 200

local function grams(token)
    local padded = "$" .. token .. "$"
    local out = {}
    for i = 1, #padded - 2 do
        out[#out + 1] = padded:sub(i, i + 2)
    end
    return out
end
TrigramIndex.grams = grams

---@param vocabulary string[]|table<string, any>  lista de tokens, ou tabela token->qualquer coisa
---@return TrigramIndex
function TrigramIndex.build(vocabulary)
    local index = setmetatable({ trigrams = {}, tokens = {} }, TrigramIndex)
    local seen = {}
    local function addToken(token)
        if seen[token] or #token < 3 then
            return
        end
        seen[token] = true
        index.tokens[#index.tokens + 1] = token
        for _, g in ipairs(grams(token)) do
            local list = index.trigrams[g]
            if not list then
                list = {}
                index.trigrams[g] = list
            end
            list[#list + 1] = token
        end
    end

    if vocabulary then
        -- aceita tanto lista {token, token, ...} quanto tabela token->valor
        local isArray = vocabulary[1] ~= nil
        if isArray then
            for _, token in ipairs(vocabulary) do
                addToken(token)
            end
        else
            for token in pairs(vocabulary) do
                addToken(token)
            end
        end
    end

    return index
end

--- @param q string  token (ou frase, com espaços) de consulta
--- @param maxDist integer
--- @return string[]  até 200 candidatos, ordenados por trigramas compartilhados desc
function TrigramIndex:candidates(q, maxDist)
    local qGrams = grams(q)
    local nGrams = #qGrams
    local shared = {}
    for _, g in ipairs(qGrams) do
        local list = self.trigrams[g]
        if list then
            for _, token in ipairs(list) do
                shared[token] = (shared[token] or 0) + 1
            end
        end
    end

    local minShared = math.max(1, nGrams - 3 * maxDist)
    local out = {}
    for token, count in pairs(shared) do
        if count >= minShared and math.abs(#token - #q) <= maxDist then
            out[#out + 1] = { token = token, shared = count }
        end
    end
    table.sort(out, function(a, b)
        if a.shared ~= b.shared then
            return a.shared > b.shared
        end
        return a.token < b.token
    end)

    local result = {}
    for i = 1, math.min(#out, MAX_CANDIDATES) do
        result[i] = out[i].token
    end
    return result
end

NS.core.TrigramIndex = TrigramIndex
