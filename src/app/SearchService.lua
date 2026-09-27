-- Orquestra o motor de busca (core/) sobre as portas injetadas (F2: texto,
-- índice, ranking. F3: fuzzy/alias. F4: parser estruturado/filtros).
local NS = SmartShopSearch
local ExactMatcher = NS.core.ExactMatcher
local FuzzyMatcher = NS.core.FuzzyMatcher
local FieldMatcher = NS.core.FieldMatcher
local AliasResolver = NS.core.AliasResolver
local NumberParser = NS.core.NumberParser
local UnitParser = NS.core.UnitParser
local ComparatorParser = NS.core.ComparatorParser
local ContextParser = NS.core.ContextParser
local QueryParser = NS.core.QueryParser
local FilterEngine = NS.core.FilterEngine
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
        queryParser = nil, -- construído sob demanda (memoização em self.deps.data)
        commonUnits = nil,
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

--- Constrói (e memoiza) o QueryParser completo a partir de deps.data
--- (LinguisticData): aliases, unidades/números/comparadores, contexto e
--- stopwords. Sem deps.data, cai para um parser mínimo (só normaliza e
--- tokeniza — todo token vira termo, como na F2).
function SearchService:_queryParser()
    if self.queryParser ~= nil then
        return self.queryParser
    end
    local data = self.deps.data
    if not data then
        self.queryParser = QueryParser.new({ normalizer = self.normalizer })
        return self.queryParser
    end

    self.commonUnits = data:commonUnits()
    local aliasResolver = AliasResolver.new(self.normalizer, data:aliases())
    local numberParser = NumberParser.new(data:numbers())
    local unitParser = UnitParser.new(self.commonUnits, data:units())
    local comparatorParser = ComparatorParser.new(data:comparators(), numberParser, unitParser, function(s)
        return self.normalizer:normalize(s)
    end)
    local contextParser = ContextParser.new(data:context(), function(s)
        return self.normalizer:normalize(s)
    end)
    local stopwordSets = data:stopwords()
    local stopwords = {}
    for _, set in ipairs(stopwordSets) do
        for word in pairs(set) do
            stopwords[word] = true
        end
    end

    self.queryParser = QueryParser.new({
        normalizer = self.normalizer,
        aliasResolver = aliasResolver,
        comparatorParser = comparatorParser,
        contextParser = contextParser,
        stopwords = stopwords,
    })
    return self.queryParser
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
--- @param ui table|nil  UiFilters
--- @return SearchResult[] results
--- @return Query query
function SearchService:_searchInner(text, ui) -- luacheck: ignore 212
    self:ensureIndex(nil)
    local index = self.deps.indexLifecycle and self.deps.indexLifecycle.index

    local parser = self:_queryParser()
    local query = parser:parse(text, self.deps.locale)

    if not index then
        return {}, query
    end
    if #query.terms == 0 and #query.concepts == 0 and #query.constraints == 0 then
        return {}, query -- RF-005: consulta vazia/só espaços/só stopwords -> sem resultado, sem erro
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
            concept.queryText,
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

    -- Filtros e constraints (F4): eliminatórios; conceitos textuais não são.
    local allowed, constraintReasons = FilterEngine.apply(index, query, ui, self.commonUnits)

    local candidateIds = {}
    if #query.terms > 0 or #query.concepts > 0 then
        for itemId in pairs(termHits) do
            candidateIds[itemId] = true
        end
        for itemId in pairs(conceptHitsByItem) do
            candidateIds[itemId] = true
        end
        if allowed then
            for itemId in pairs(candidateIds) do
                if not allowed[itemId] then
                    candidateIds[itemId] = nil
                end
            end
        end
    elseif allowed then
        candidateIds = allowed
    else
        candidateIds = {} -- sem termos/conceitos/constraints (não deveria ocorrer; RF-005 já tratou vazio)
    end

    local maxResults = self.deps.settings and self.deps.settings:get("search#maxResults") or 300

    local results = {}
    for itemId in pairs(candidateIds) do
        local item = index.items[itemId]
        local score, coverage, reasons =
            SearchScorer.score(query, item, termHits[itemId] or {}, conceptHitsByItem[itemId] or {}, self.weights)
        for _, r in ipairs(constraintReasons[itemId] or {}) do
            reasons[#reasons + 1] = r
        end
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
