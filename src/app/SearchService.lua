-- Orquestra o motor de busca (core/) sobre as portas injetadas (F2: texto,
-- índice, ranking. F3: fuzzy/alias. F4+: parser estruturado/filtros).
local NS = SmartShopSearch
local Tokenizer = NS.core.Tokenizer
local ExactMatcher = NS.core.ExactMatcher
local FuzzyMatcher = NS.core.FuzzyMatcher
local FieldMatcher = NS.core.FieldMatcher
local AliasResolver = NS.core.AliasResolver
local SearchScorer = NS.core.SearchScorer
local Ranker = NS.core.Ranker
local IdMatcher = NS.core.IdMatcher
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
        aliasResolver = nil, -- construído sob demanda (memoização em self.deps.data)
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

--- Constrói (e memoiza) o AliasResolver a partir de deps.data (LinguisticData).
--- Sem deps.data, a busca segue funcionando só por texto (sem conceitos).
function SearchService:_aliasResolver()
    if self.aliasResolver ~= nil then
        return self.aliasResolver or nil
    end
    if self.deps.data then
        self.aliasResolver = AliasResolver.new(self.normalizer, self.deps.data:aliases())
    else
        self.aliasResolver = false -- memoiza "sem resolver" para não tentar de novo
    end
    return self.aliasResolver or nil
end

local function emptyQuery(text)
    return { raw = text, terms = {}, concepts = {}, constraints = {}, context = nil, locale = "en", warnings = {} }
end

--- Itens que satisfazem um QueryConcept (categoria/marca/espécie/origem),
--- via facet do índice; ids de conceito aceitam curinga de prefixo ("TRACTORS*").
local function conceptItemIds(index, concept)
    local facet = index.facets[concept.kind]
    local ids = {}
    if not facet then
        return ids
    end
    for key, itemSet in pairs(facet) do
        if IdMatcher.matches(concept.value, key) then
            for itemId in pairs(itemSet) do
                ids[itemId] = true
            end
        end
    end
    return ids
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

    local tokens = Tokenizer.tokenize(norm)
    local query = emptyQuery(text)

    if not index then
        for _, tok in ipairs(tokens) do
            query.terms[#query.terms + 1] = { text = tok.text, span = { tok.s, tok.e }, fuzzyMax = 0 }
        end
        return {}, query
    end

    local resolver = self:_aliasResolver()

    -- Varredura esquerda->direita: cada posição vira um QueryConcept (alias,
    -- possivelmente de frase) ou um QueryTerm (RF-034/036 simplificado; o
    -- QueryParser completo, com números/unidades/comparadores, é da F4).
    local i = 1
    while i <= #tokens do
        local resolved = resolver and resolver:resolveAt(tokens, i, true)
        if resolved then
            local parts = {}
            for k = 0, resolved.consumed - 1 do
                parts[#parts + 1] = tokens[i + k].text
            end
            query.concepts[#query.concepts + 1] = {
                kind = resolved.kind,
                value = resolved.id,
                confidence = resolved.confidence,
                span = resolved.span,
                queryText = table.concat(parts, " "),
                consumed = resolved.consumed,
            }
            i = i + resolved.consumed
        else
            local tok = tokens[i]
            query.terms[#query.terms + 1] = { text = tok.text, span = { tok.s, tok.e }, fuzzyMax = 0 }
            i = i + 1
        end
    end

    for _, term in ipairs(query.terms) do
        term.idf = index.idf[term.text] or 1
    end

    -- termHits[itemId][termIndex] = melhor (campo, tipo) para aquele termo naquele item.
    -- Fuzzy só roda quando o exato/prefixo não achou nada para o termo (economia).
    local termHits = {}
    for i2, term in ipairs(query.terms) do
        local candidates = ExactMatcher.match(index, term.text)
        if next(candidates) == nil then
            candidates = FuzzyMatcher.matchToken(index, term.text)
        end
        for itemId in pairs(candidates) do
            local hit = FieldMatcher.best(candidates, itemId, self.weights, term.text)
            if hit then
                termHits[itemId] = termHits[itemId] or {}
                termHits[itemId][i2] = hit
            end
        end
    end

    -- conceptHitsByItem[itemId][concept] = MatchReason (RF-051)
    local conceptHitsByItem = {}
    for _, concept in ipairs(query.concepts) do
        local weight = self.weights.concept * concept.confidence
        local reason = Models.reason(
            "alias",
            concept.kind,
            query.raw,
            concept.value,
            "confiança " .. tostring(concept.confidence),
            weight
        )
        local facetIds = conceptItemIds(index, concept)
        for itemId in pairs(facetIds) do
            conceptHitsByItem[itemId] = conceptHitsByItem[itemId] or {}
            conceptHitsByItem[itemId][concept] = reason
        end

        -- Bônus (AC-RNK-01): um item que NÃO satisfaz o facet do conceito
        -- (ex.: marca diferente), mas cujo texto no MESMO campo do conceito
        -- se parece (exato/fuzzy) com o termo que originou o conceito — ex.
        -- um mod chamado "Fent Custom Trailer" para o conceito brand=FENDT
        -- vindo da consulta "fendt". Só para conceitos de 1 token (frases
        -- de alias não têm essa checagem — fora de escopo desta fase).
        if
            concept.consumed == 1
            and concept.confidence >= 1.0
            and (concept.kind == "brand" or concept.kind == "category")
        then
            -- Aqui NÃO economiza fuzzy quando o exato já achou algo: o
            -- objetivo é justamente achar impostores/typos (ex. "Fent") que
            -- coexistem com marcas reais que também casam por exato.
            local textCandidates = FuzzyMatcher.matchToken(index, concept.queryText)
            for itemId in pairs(textCandidates) do
                if not facetIds[itemId] then
                    local hit = FieldMatcher.best(textCandidates, itemId, self.weights, concept.queryText)
                    if hit then
                        conceptHitsByItem[itemId] = conceptHitsByItem[itemId] or {}
                        conceptHitsByItem[itemId][concept] = hit.reason
                    end
                end
            end
        end
    end

    local candidateIds = {}
    for itemId in pairs(termHits) do
        candidateIds[itemId] = true
    end
    for itemId in pairs(conceptHitsByItem) do
        candidateIds[itemId] = true
    end

    local maxResults = self.deps.settings and self.deps.settings:get("search#maxResults") or 300

    local results = {}
    for itemId in pairs(candidateIds) do
        local item = index.items[itemId]
        local score, coverage, reasons =
            SearchScorer.score(query, item, termHits[itemId] or {}, conceptHitsByItem[itemId] or {}, self.weights)
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
