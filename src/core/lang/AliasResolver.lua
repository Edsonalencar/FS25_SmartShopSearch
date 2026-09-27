-- Resolve tokens/frases da consulta em conceitos (categoria, marca, espécie,
-- origem) a partir de dados de alias carregados por locale (ADR-06). Nunca
-- lê arquivo: recebe os dados já parseados (porta DataLoader/LinguisticData).
local NS = SmartShopSearch
local Osa = NS.core.Osa
local TrigramIndex = NS.core.TrigramIndex
local FuzzyMatcher = NS.core.FuzzyMatcher

local AliasResolver = {}
AliasResolver.__index = AliasResolver

---@class AliasConcept  -- já parseado (porta DataLoader); nunca lê arquivo
---@field kind string
---@field id string
---@field terms string[]

---@param normalizer TextNormalizer
---@param dataList AliasConcept[][]  uma lista de listas de conceitos, uma por
---locale carregado (idioma do jogo primeiro, depois "en" — S-06), já na
---ordem de prioridade (a primeira ocorrência de um termo vence).
function AliasResolver.new(normalizer, dataList)
    local single = {} -- term normalizado (1 palavra) -> {kind, id}
    local multi = {} -- primeiro token -> lista de {tokens[], kind, id}, maior frase primeiro
    local allPhrases = {} -- term normalizado (1+ palavras) -> {kind, id} — usado no fuzzy

    local function addTerm(term, kind, id)
        local norm = normalizer:normalize(term)
        if norm == "" then
            return
        end
        local tokens = {}
        for tok in norm:gmatch("%S+") do
            tokens[#tokens + 1] = tok
        end
        if #tokens == 0 then
            return
        end
        if not allPhrases[norm] then
            allPhrases[norm] = { kind = kind, id = id }
        end
        if #tokens == 1 then
            if not single[norm] then
                single[norm] = { kind = kind, id = id }
            end
        else
            local first = tokens[1]
            multi[first] = multi[first] or {}
            multi[first][#multi[first] + 1] = { tokens = tokens, kind = kind, id = id }
        end
    end

    for _, concepts in ipairs(dataList or {}) do
        for _, concept in ipairs(concepts) do
            for _, term in ipairs(concept.terms) do
                addTerm(term, concept.kind, concept.id)
            end
        end
    end

    for _, list in pairs(multi) do
        table.sort(list, function(a, b)
            return #a.tokens > #b.tokens
        end)
    end

    return setmetatable({
        single = single,
        multi = multi,
        allPhrases = allPhrases,
        trigramIndex = TrigramIndex.build(allPhrases),
    }, AliasResolver)
end

--- @param tokens {text:string, s:integer, e:integer}[]
--- @param i integer
--- @param fuzzy boolean  se falso, só tenta correspondência exata (frase/single)
--- @return {kind:string, id:string, confidence:number, span:integer[], consumed:integer}|nil
function AliasResolver:resolveAt(tokens, i, fuzzy)
    -- 1. frase multi-palavra exata (maior primeiro)
    local multiCandidates = self.multi[tokens[i].text]
    if multiCandidates then
        for _, cand in ipairs(multiCandidates) do
            local n = #cand.tokens
            if i + n - 1 <= #tokens then
                local ok = true
                for k = 1, n do
                    if tokens[i + k - 1].text ~= cand.tokens[k] then
                        ok = false
                        break
                    end
                end
                if ok then
                    return {
                        kind = cand.kind,
                        id = cand.id,
                        confidence = 1.0,
                        span = { tokens[i].s, tokens[i + n - 1].e },
                        consumed = n,
                    }
                end
            end
        end
    end

    -- 2. single-palavra exata
    local single = self.single[tokens[i].text]
    if single then
        return {
            kind = single.kind,
            id = single.id,
            confidence = 1.0,
            span = { tokens[i].s, tokens[i].e },
            consumed = 1,
        }
    end

    if not fuzzy then
        return nil
    end

    -- 3a. fuzzy de frase (2-3 tokens), limiar pelo comprimento sem espaços (L6)
    local phraseMatch = FuzzyMatcher.matchPhraseWindow(self.trigramIndex, tokens, i, 3)
    if phraseMatch then
        local entry = self.allPhrases[phraseMatch.matched]
        if entry then
            local w = phraseMatch.consumed
            return {
                kind = entry.kind,
                id = entry.id,
                confidence = phraseMatch.sim,
                span = { tokens[i].s, tokens[i + w - 1].e },
                consumed = w,
            }
        end
    end

    -- 3b. fuzzy de token único, contra os termos de alias de 1 palavra
    local maxDist = FuzzyMatcher.maxDistFor(#tokens[i].text)
    if maxDist > 0 then
        local best, bestDist = nil, maxDist + 1
        for _, cand in ipairs(self.trigramIndex:candidates(tokens[i].text, maxDist)) do
            if not cand:find(" ", 1, true) then
                local dist = Osa.distance(tokens[i].text, cand, maxDist)
                if dist < bestDist then
                    bestDist, best = dist, cand
                end
            end
        end
        if best then
            local entry = self.allPhrases[best]
            local sim = 1 - bestDist / math.max(#tokens[i].text, #best)
            return {
                kind = entry.kind,
                id = entry.id,
                confidence = sim,
                span = { tokens[i].s, tokens[i].e },
                consumed = 1,
            }
        end
    end

    return nil
end

NS.core.AliasResolver = AliasResolver
