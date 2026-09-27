-- Escolhe, por item e por termo, o melhor par (campo, tipo) entre os
-- candidatos produzidos pelos matchers (Exact/Prefix/Alias/Fuzzy), segundo
-- wCampo * wTipo * sim, e gera o MatchReason correspondente (RF-051).
local NS = SmartShopSearch
local Models = NS.core.Models
local FieldMatcher = {}

local function typeWeight(weights, kind)
    return weights.types[kind] or weights.types.exact
end

--- @param candidates table<integer, table<string, {kind:string, sim:number, matched:string}>>
--- @param itemId integer
--- @param weights table  (core/rank/Weights)
--- @param queryText string  trecho da consulta que originou o termo (para o MatchReason)
--- @return {value:number, reason:MatchReason, field:string, kind:string, sim:number}|nil
function FieldMatcher.best(candidates, itemId, weights, queryText)
    local byField = candidates[itemId]
    if not byField then
        return nil
    end
    local bestScore, bestField, bestInfo = -1, nil, nil
    for field, info in pairs(byField) do
        local wCampo = weights.fields[field] or weights.fields.spec
        local score = wCampo * typeWeight(weights, info.kind) * info.sim
        if score > bestScore then
            bestScore, bestField, bestInfo = score, field, info
        end
    end
    if not bestField then
        return nil
    end
    local detail = nil
    if bestInfo.kind == "fuzzy1" or bestInfo.kind == "fuzzy2" then
        detail = "distância " .. (bestInfo.kind == "fuzzy1" and "1" or "2+")
    end
    local reason = Models.reason(bestInfo.kind, bestField, queryText, bestInfo.matched, detail, bestScore)
    return { value = bestScore, reason = reason, field = bestField, kind = bestInfo.kind, sim = bestInfo.sim }
end

NS.core.FieldMatcher = FieldMatcher
