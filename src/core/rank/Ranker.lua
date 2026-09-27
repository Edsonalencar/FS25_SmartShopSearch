-- Ordena e corta os SearchResult (PRD §6.6): score desc, coverage desc, nome
-- asc (determinístico); corte por score mínimo relativo/absoluto e por
-- maxResults.
local NS = SmartShopSearch
local Ranker = {}

local function nameOf(result)
    local field = result.item.fields and result.item.fields.name
    return (field and field.norm) or ""
end

local function compare(a, b)
    if a.score ~= b.score then
        return a.score > b.score
    end
    if a.coverage ~= b.coverage then
        return a.coverage > b.coverage
    end
    return nameOf(a) < nameOf(b)
end

---@param results SearchResult[]
---@param weights table  core/rank/Weights
---@param maxResults integer|nil
---@return SearchResult[]
function Ranker.rank(results, weights, maxResults)
    local sorted = {}
    for i, r in ipairs(results) do
        sorted[i] = r
    end
    table.sort(sorted, compare)

    if #sorted == 0 then
        return sorted
    end

    local best = sorted[1].score
    local threshold = math.max(weights.minScoreAbs, weights.minScoreRel * best)

    local out = {}
    for _, r in ipairs(sorted) do
        if r.score < threshold then
            break
        end
        out[#out + 1] = r
        if maxResults and #out >= maxResults then
            break
        end
    end
    return out
end

NS.core.Ranker = Ranker
