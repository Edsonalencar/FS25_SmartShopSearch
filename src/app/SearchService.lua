-- Orquestra o motor de busca (core/) sobre as portas injetadas (F2: texto,
-- índice, ranking. F3+: fuzzy/alias. F4+: parser estruturado/filtros).
local NS = SmartShopSearch
local Tokenizer = NS.core.Tokenizer
local ExactMatcher = NS.core.ExactMatcher
local FieldMatcher = NS.core.FieldMatcher
local SearchScorer = NS.core.SearchScorer
local Ranker = NS.core.Ranker
local DefaultWeights = NS.core.Weights
local Models = NS.core.Models

local SearchService = {}
SearchService.__index = SearchService

---@param deps {indexLifecycle:table, logger:table, clock:table|nil, data:table|nil,
---settings:table|nil, normalizer:table, weights:table|nil}
function SearchService.new(deps)
    deps = deps or {}
    assert(deps.normalizer, "SearchService requer deps.normalizer (core/text/TextNormalizer)")
    return setmetatable({
        deps = deps,
        normalizer = deps.normalizer,
        weights = deps.weights or DefaultWeights,
    }, SearchService)
end

---@param budgetSec number|nil
---@return boolean ready
function SearchService:ensureIndex(budgetSec)
    if not self.deps.indexLifecycle then
        return false
    end
    return self.deps.indexLifecycle:ensure(budgetSec)
end

local function emptyQuery(text)
    return { raw = text, terms = {}, concepts = {}, constraints = {}, context = nil, locale = "en", warnings = {} }
end

--- @param text string
--- @param ui table|nil  UiFilters (aplicado a partir da F4)
--- @return SearchResult[] results
--- @return Query query
function SearchService:_searchInner(text, ui) -- luacheck: ignore 212
    if type(text) ~= "string" then
        return {}, emptyQuery(text)
    end

    self:ensureIndex(nil)
    local index = self.deps.indexLifecycle and self.deps.indexLifecycle.index

    local norm = self.normalizer:normalize(text)
    if norm == "" then
        return {}, emptyQuery(text) -- RF-005: consulta vazia/só espaços -> sem resultado, sem erro
    end

    local query = emptyQuery(text)
    for _, tok in ipairs(Tokenizer.tokenize(norm)) do
        query.terms[#query.terms + 1] = { text = tok.text, span = { tok.s, tok.e }, fuzzyMax = 0 }
    end

    if not index then
        return {}, query
    end

    for _, term in ipairs(query.terms) do
        term.idf = index.idf[term.text] or 1
    end

    -- termHits[itemId][termIndex] = melhor (campo, tipo) para aquele termo naquele item
    local termHits = {}
    for i, term in ipairs(query.terms) do
        local candidates = ExactMatcher.match(index, term.text)
        for itemId in pairs(candidates) do
            local hit = FieldMatcher.best(candidates, itemId, self.weights, term.text)
            if hit then
                termHits[itemId] = termHits[itemId] or {}
                termHits[itemId][i] = hit
            end
        end
    end

    local maxResults = self.deps.settings and self.deps.settings:get("search#maxResults") or 300

    local results = {}
    for itemId, hitsForItem in pairs(termHits) do
        local item = index.items[itemId]
        local score, coverage, reasons = SearchScorer.score(query, item, hitsForItem, {}, self.weights)
        results[#results + 1] = Models.result(item, score, coverage, reasons)
    end

    return Ranker.rank(results, self.weights, maxResults), query
end

---@param text string
---@param ui table|nil
---@return SearchResult[] results
---@return Query|nil query
function SearchService:search(text, ui)
    local SafeCall = NS.app.SafeCall
    local results, query = SafeCall.run("search", function()
        return self:_searchInner(text, ui)
    end)
    return results or {}, query
end

NS.app.SearchService = SearchService
