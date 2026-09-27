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
local CompatibilityResolver = NS.core.CompatibilityResolver
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

--- Escolhe o alvo de "compatível com X" quando a consulta não usa "este/
--- selecionado" (F8, RF-049): busca só de texto sobre `targetTerms`, usando
--- o top-1 apenas se score >= 0.6 e a distância para o 2º for >= 0.1. A
--- escolha do ALVO usa texto; a compatibilidade em si nunca usa (RF-050).
function SearchService:_resolveCompatTextTarget(index, query)
    local words = query.context.targetTerms
    if not words or #words == 0 then
        return nil
    end
    local hitsByItem = {}
    for i, word in ipairs(words) do
        local candidates = ExactMatcher.match(index, word)
        for itemId in pairs(candidates) do
            local hit = FieldMatcher.best(candidates, itemId, self.weights, word)
            if hit then
                hitsByItem[itemId] = hitsByItem[itemId] or {}
                hitsByItem[itemId][i] = hit
            end
        end
    end
    local termsQuery = { terms = {} }
    for i, word in ipairs(words) do
        termsQuery.terms[i] = { text = word, idf = index.idf[word] or 1 }
    end
    local scored = {}
    for itemId, hits in pairs(hitsByItem) do
        local s = SearchScorer.score(termsQuery, index.items[itemId], hits, {}, self.weights)
        scored[#scored + 1] = { id = itemId, score = s }
    end
    table.sort(scored, function(a, b)
        return a.score > b.score
    end)
    if #scored == 0 or scored[1].score < 0.6 then
        query.warnings[#query.warnings + 1] = "alvo de compatibilidade não encontrado"
        return nil
    end
    if scored[2] and (scored[1].score - scored[2].score) < 0.1 then
        query.warnings[#query.warnings + 1] = "alvo de compatibilidade ambíguo"
        return nil
    end
    return index.items[scored[1].id]
end

--- Resolve "compatível com este/selecionado" ou "compatível com <texto>"
--- (F8): compara o alvo contra todos os itens via CompatibilityResolver
--- (core, RF-050 — nunca por texto) e devolve os resultados já rankeados.
--- Só roda se houver um adapters.CompatibilityExtractor injetado.
function SearchService:_searchCompat(index, query)
    local extractor = self.deps.compatibilityExtractor
    if not extractor then
        query.warnings[#query.warnings + 1] = "compatibilidade indisponível"
        return {}
    end

    local targetItem
    if query.context.target == "selected" then
        targetItem = self.deps.selectedItemFn and self.deps.selectedItemFn()
        if not targetItem then
            query.warnings[#query.warnings + 1] = "nenhum item selecionado para compatibilidade"
        end
    else
        targetItem = self:_resolveCompatTextTarget(index, query)
    end
    if not targetItem then
        return {}
    end

    local targetInfo = extractor:infoFor(targetItem)
    if not targetInfo then
        query.warnings[#query.warnings + 1] = "sem dados de compatibilidade para o alvo"
        return {}
    end

    -- Heurística de papel (F8, sem F5 para confirmar): itens de espécie
    -- "vehicle" são o veículo; os demais são avaliados como implemento.
    local targetIsVehicle = targetItem.species == "vehicle"

    local results = {}
    for _, item in ipairs(index.items) do
        if item.id ~= targetItem.id then
            local itemInfo = extractor:infoFor(item)
            if itemInfo then
                local vehicleInfo = targetIsVehicle and targetInfo or itemInfo
                local implementInfo = targetIsVehicle and itemInfo or targetInfo
                local compat = CompatibilityResolver.evaluate(vehicleInfo, implementInfo)
                if compat then
                    local weight = (compat.level == "declared") and self.weights.compat.declared
                        or self.weights.compat.joint
                    local detail = table.concat(compat.evidence, "; ")
                    if compat.powerOk == false then
                        weight = math.max(0, weight - self.weights.compat.powerInsufficient)
                        detail = detail .. " (potência insuficiente)"
                    end
                    local reason = Models.reason("compat", "compat", query.raw, item.xmlFilename, detail, weight)
                    results[#results + 1] = Models.result(item, math.min(1, weight), 1, { reason })
                end
            end
        end
    end

    local maxResults = self.deps.settings and self.deps.settings:get("search#maxResults") or 300
    return Ranker.rank(results, self.weights, maxResults)
end

--- Fuzzy de frase contra textos de itens (ADR-14): quando algum termo não
--- teve hit exato, tenta casar janelas de 2–3 termos com as frases
--- multi-palavra do índice (ex. "deuts far" → "deutz fahr"). O hit vale para
--- todos os termos da janela, no campo de origem da frase.
function SearchService:_phraseHits(index, query, termHits, termMatched, allowed)
    local needsHelp, anyNeeds = {}, false
    for i2 in ipairs(query.terms) do
        if not termMatched[i2] then
            needsHelp[i2] = true
            anyNeeds = true
        end
    end
    if not anyNeeds or #query.terms < 2 then
        return
    end
    local W = self.weights
    for _, pm in ipairs(FuzzyMatcher.matchItemPhrases(index, query.terms, needsHelp)) do
        local kind = FuzzyMatcher.kindForDist(pm.dist)
        local parts = {}
        for k = pm.first, pm.first + pm.consumed - 1 do
            parts[#parts + 1] = query.terms[k].text
        end
        local phraseText = table.concat(parts, " ")
        for itemId, fields in pairs(FuzzyMatcher.itemsWithPhrase(index, pm.matched)) do
            if not allowed or allowed[itemId] then
                local bestField, bestW = nil, -1
                for field in pairs(fields) do
                    local w = W.fields[field] or W.fields.spec
                    if w > bestW then
                        bestField, bestW = field, w
                    end
                end
                local value = bestW * (W.types[kind] or W.types.exact) * pm.sim
                local reason =
                    Models.reason(kind, bestField, phraseText, pm.matched, "frase, distância " .. pm.dist, value)
                local hit =
                    { value = value, reason = reason, field = bestField, kind = kind, sim = pm.sim, dist = pm.dist }
                hit.fuzzyMax = pm.maxDist
                for k = pm.first, pm.first + pm.consumed - 1 do
                    local byTerm = termHits[itemId]
                    if not byTerm then
                        byTerm = {}
                        termHits[itemId] = byTerm
                    end
                    if not byTerm[k] or byTerm[k].value < value then
                        byTerm[k] = hit
                    end
                end
            end
        end
    end
end

--- @param text string
--- @param ui table|nil  UiFilters
--- @return SearchResult[] results
--- @return Query query
function SearchService:_searchInner(text, ui) -- luacheck: ignore 212
    -- Só constrói se ainda não há índice: revalidar a assinatura relê o
    -- catálogo inteiro, e isso já acontece na abertura da loja (ADR-04), não
    -- a cada busca.
    local lifecycle = self.deps.indexLifecycle
    if not (lifecycle and lifecycle.index) then
        self:ensureIndex(nil)
    end
    local index = lifecycle and lifecycle.index

    local parser = self:_queryParser()
    local query = parser:parse(text, self.deps.locale)

    if index and query.context and query.context.kind == "compatibleWith" then
        return self:_searchCompat(index, query), query
    end

    if not index then
        return {}, query
    end
    if #query.terms == 0 and #query.concepts == 0 and #query.constraints == 0 then
        return {}, query -- RF-005: consulta vazia/só espaços/só stopwords -> sem resultado, sem erro
    end

    for _, term in ipairs(query.terms) do
        term.idf = index.idf[term.text] or 1
    end

    -- Filtros e constraints (F4): eliminatórios; conceitos textuais não são.
    -- Aplicados antes do matching para não montar hits/motivos de itens que
    -- os filtros já eliminaram (PRD §15: sem alocação por item descartado).
    local allowed = FilterEngine.apply(index, query, ui, self.commonUnits)

    -- termHits[itemId][termIndex] = melhor (campo, tipo) para aquele termo naquele item.
    -- Fuzzy só roda quando o exato/prefixo não achou nada para o termo (economia).
    local termHits = {}
    local termMatched = {}
    for i2, term in ipairs(query.terms) do
        local candidates = ExactMatcher.match(index, term.text)
        if next(candidates) == nil then
            candidates = FuzzyMatcher.matchToken(index, term.text)
        end
        -- "casou de verdade" = o token existe no vocabulário (hit exato);
        -- prefixo/fuzzy isolados ainda podem ser melhorados pelo fuzzy de frase.
        termMatched[i2] = index:postingsFor(term.text) ~= nil
        for itemId in pairs(candidates) do
            if not allowed or allowed[itemId] then
                local hit = FieldMatcher.best(candidates, itemId, self.weights, term.text)
                if hit then
                    termHits[itemId] = termHits[itemId] or {}
                    termHits[itemId][i2] = hit
                end
            end
        end
    end

    self:_phraseHits(index, query, termHits, termMatched, allowed)

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
            if not allowed or allowed[itemId] then
                conceptHitsByItem[itemId] = conceptHitsByItem[itemId] or {}
                conceptHitsByItem[itemId][concept] = reason
            end
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
                if not facetIds[itemId] and (not allowed or allowed[itemId]) then
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
        results[#results + 1] = Models.result(item, score, coverage, reasons)
    end

    -- Motivos de constraint (peso 0, só explicação) só para o que sobrou do
    -- corte do Ranker, não para todos os itens aprovados pelos filtros.
    local ranked = Ranker.rank(results, self.weights, maxResults)
    if #query.constraints > 0 then
        for _, r in ipairs(ranked) do
            for _, reason in ipairs(FilterEngine.reasonsFor(r.item, query, self.commonUnits)) do
                r.reasons[#r.reasons + 1] = reason
            end
        end
    end
    return ranked, query
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
