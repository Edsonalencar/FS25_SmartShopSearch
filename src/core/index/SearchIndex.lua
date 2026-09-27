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
---@field numeric table<string, {value:number, id:integer}[]>
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
        signature = nil,
    }, SearchIndex)
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
        fields = {}
        byItem[itemId] = fields
        self.vocabulary[token] = self.vocabulary[token] + 1
    end
    fields[field] = true
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

local function lowerBound(list, value)
    local lo, hi = 1, #list + 1
    while lo < hi do
        local mid = math.floor((lo + hi) / 2)
        if list[mid].value < value then
            lo = mid + 1
        else
            hi = mid
        end
    end
    return lo
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
    local from = min and lowerBound(list, min) or 1
    local toExclusive = #list + 1
    if max then
        toExclusive = lowerBound(list, max)
        -- inclui valores == max (lowerBound aponta para o primeiro >= max)
        while list[toExclusive] and list[toExclusive].value == max do
            toExclusive = toExclusive + 1
        end
    end
    for i = from, toExclusive - 1 do
        out[list[i].id] = true
    end
    return out
end

NS.core.SearchIndex = SearchIndex
