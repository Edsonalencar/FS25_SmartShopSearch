-- Estrutura de dados do índice invertido (PRD §6.1). Construída por
-- IndexBuilder; consultada por ExactMatcher/FuzzyMatcher/FilterEngine.
local NS = SmartShopSearch
local SearchIndex = {}
SearchIndex.__index = SearchIndex

local PREFIX_MIN, PREFIX_MAX = 2, 6
local PREFIX_LIMIT = 50

---@class SearchIndex
---@field items IndexedItem[]
---@field postings table<string, table<integer, table<string, boolean>>>  -- token -> itemId -> {field=true}
---@field vocabulary table<string, integer>   -- df
---@field idf table<string, number>
---@field prefixes table<string, string[]>    -- prefixo (2..6 bytes) -> tokens
---@field facets {brand:table, category:table, origin:table, species:table}
---@field numeric table<string, {values:number[], ids:integer[]}>  -- arrays paralelos, ordenados por valor
---@field phrases table<string, table<string, boolean>>  -- frase normalizada multi-palavra -> {campo=true}
---@field fieldSets table<string, table<string, boolean>>  -- conjuntos de campos compartilhados (postings)
---@field signature string
function SearchIndex.new()
    return setmetatable({
        items = {},
        postings = {},
        vocabulary = {},
        idf = {},
        prefixes = {},
        facets = { brand = {}, category = {}, origin = {}, species = {} },
        numeric = {},
        phrases = {},
        fieldSets = {},
        signature = nil,
    }, SearchIndex)
end

--- Conjunto de campos canônico e compartilhado (RNF-003): quase todo posting
--- é {name=true}, {brand=true}…, então em vez de uma tabela por par
--- (token, item) o índice guarda uma por combinação de campos. Somente
--- leitura para os consumidores (ExactMatcher/FuzzyMatcher só iteram).
function SearchIndex:_fieldSet(base, field)
    if not base then
        local set = self.fieldSets[field]
        if not set then
            set = { [field] = true }
            self.fieldSets[field] = set
        end
        return set
    end
    local names = { field }
    for f in pairs(base) do
        names[#names + 1] = f
    end
    table.sort(names)
    local key = table.concat(names, ",")
    local set = self.fieldSets[key]
    if not set then
        set = {}
        for _, f in ipairs(names) do
            set[f] = true
        end
        self.fieldSets[key] = set
    end
    return set
end

--- Registra `token` como presente em `itemId`, no campo `field`.
function SearchIndex:addPosting(token, itemId, field)
    local byItem = self.postings[token]
    if not byItem then
        byItem = {}
        self.postings[token] = byItem
        self.vocabulary[token] = 0
    end
    local fields = byItem[itemId]
    if not fields then
        byItem[itemId] = self:_fieldSet(nil, field)
        self.vocabulary[token] = self.vocabulary[token] + 1
    elseif not fields[field] then
        byItem[itemId] = self:_fieldSet(fields, field)
    end
end

--- Indexa os prefixos de 2..6 bytes de `token` (chamado uma vez por token
--- novo do vocabulário, ao final da construção).
function SearchIndex:indexPrefixes(token)
    local maxLen = math.min(PREFIX_MAX, #token)
    for len = PREFIX_MIN, maxLen do
        local p = token:sub(1, len)
        local list = self.prefixes[p]
        if not list then
            list = {}
            self.prefixes[p] = list
        end
        list[#list + 1] = token
    end
end

---@param p string  prefixo de 2..6 bytes
---@return string[]
function SearchIndex:tokensWithPrefix(p)
    if #p > PREFIX_MAX then
        p = p:sub(1, PREFIX_MAX)
    end
    local list = self.prefixes[p]
    if not list then
        return {}
    end
    if #list <= PREFIX_LIMIT then
        return list
    end
    local out = {}
    for i = 1, PREFIX_LIMIT do
        out[i] = list[i]
    end
    return out
end

---@param token string
---@return table<integer, table<string, boolean>>|nil
function SearchIndex:postingsFor(token)
    return self.postings[token]
end

local function lowerBound(values, value)
    local lo, hi = 1, #values + 1
    while lo < hi do
        local mid = math.floor((lo + hi) / 2)
        if values[mid] < value then
            lo = mid + 1
        else
            hi = mid
        end
    end
    return lo
end

--- Substitui a faixa numérica de `spec` a partir de pares {value, id}
--- (ordena e converte para arrays paralelos, sem uma tabela por item).
---@param spec string
---@param pairsList {value:number, id:integer}[]
function SearchIndex:setNumeric(spec, pairsList)
    table.sort(pairsList, function(a, b)
        if a.value ~= b.value then
            return a.value < b.value
        end
        return a.id < b.id
    end)
    local values, ids = {}, {}
    for i, p in ipairs(pairsList) do
        values[i], ids[i] = p.value, p.id
    end
    self.numeric[spec] = { values = values, ids = ids }
end

--- Retorna o conjunto de itemIds cujo valor de `spec` está em [min, max]
--- (qualquer extremo pode ser nil), via busca binária em `numeric[spec]`.
---@param spec string
---@param min number|nil
---@param max number|nil
---@return table<integer, boolean>
function SearchIndex:rangeIds(spec, min, max)
    local list = self.numeric[spec]
    local out = {}
    if not list then
        return out
    end
    local values, ids = list.values, list.ids
    local from = min and lowerBound(values, min) or 1
    local toExclusive = #values + 1
    if max then
        toExclusive = lowerBound(values, max)
        -- inclui valores == max (lowerBound aponta para o primeiro >= max)
        while values[toExclusive] and values[toExclusive] == max do
            toExclusive = toExclusive + 1
        end
    end
    for i = from, toExclusive - 1 do
        out[ids[i]] = true
    end
    return out
end

NS.core.SearchIndex = SearchIndex
