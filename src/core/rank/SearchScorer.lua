-- Modelo de score (§2.4 do spec, L11): normalizado pelo máximo teórico da
-- própria consulta, multiplicado por um fator de cobertura, menos penalidades.
--
-- raw(item) = Σ_t best_t(item) + Σ_c wConcept·conf_c·sat_c(item)
-- max       = Σ_t (1.0·1.0·1·idf_t) + Σ_c wConcept·conf_c        (máximo teórico da consulta)
-- coverage  = (termos satisfeitos + conceitos satisfeitos) / (termos + conceitos)
-- score     = clamp01( raw/max · (floor + (1-floor)·coverage) − penalidades )
local NS = SmartShopSearch
local Utf8 = NS.core.Utf8
local SearchScorer = {}

local SECONDARY_FIELDS = { mod = true, author = true, dlc = true }

--- @param query Query
--- @param termHits table<integer, {value:number, reason:MatchReason, field:string, kind:string,
---dist:integer|nil, fuzzyMax:integer|nil}>
--- @param W table  core/rank/Weights
local function penalties(query, termHits, W)
    local penalty = 0
    local anyHit, allSecondary = false, true
    for i, term in ipairs(query.terms) do
        local h = termHits[i]
        if h then
            anyHit = true
            if not SECONDARY_FIELDS[h.field] then
                allSecondary = false
            end
            if h.kind == "prefix" and Utf8.len(term.text) <= 3 then
                penalty = penalty + W.penalty.shortToken
            end
            if h.dist and h.fuzzyMax and h.dist >= h.fuzzyMax then
                penalty = penalty + W.penalty.fuzzyFar
            end
        end
    end
    if anyHit and allSecondary then
        penalty = penalty + W.penalty.secondaryOnly
    end
    return penalty
end
SearchScorer.penalties = penalties

--- @param query Query
--- @param item IndexedItem
--- @param termHits table<integer, table>
--- @param conceptHits table<table, MatchReason>
--- @param W table
--- @return number score, number coverage, MatchReason[] reasons
function SearchScorer.score(query, item, termHits, conceptHits, W) -- luacheck: ignore 212
    local raw, max, hit, total, reasons = 0, 0, 0, 0, {}

    for i, term in ipairs(query.terms) do
        local idf = term.idf or 1
        max = max + idf
        total = total + 1
        local h = termHits[i]
        if h then
            raw = raw + h.value * idf
            hit = hit + 1
            reasons[#reasons + 1] = h.reason
        end
    end

    for _, c in ipairs(query.concepts) do
        local w = W.concept * c.confidence
        max = max + w
        total = total + 1
        local h = conceptHits[c]
        if h then
            raw = raw + w
            hit = hit + 1
            reasons[#reasons + 1] = h
        end
    end

    if total == 0 then
        return 1, 1, reasons -- consulta só com constraints/filtros
    end

    local coverage = hit / total
    local s = (raw / max) * (W.coverageFloor + (1 - W.coverageFloor) * coverage)
    s = s - penalties(query, termHits, W)
    if s < 0 then
        s = 0
    elseif s > 1 then
        s = 1
    end
    return s, coverage, reasons
end

NS.core.SearchScorer = SearchScorer
