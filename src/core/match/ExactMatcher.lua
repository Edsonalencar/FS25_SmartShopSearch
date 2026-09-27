-- Matching exato e por prefixo sobre o índice invertido (F2). Fuzzy (F3) e
-- alias (F3) entram depois na ordem: exato -> prefixo -> alias -> fuzzy.
local NS = SmartShopSearch
local ExactMatcher = {}

--- @param index SearchIndex
--- @param token string  token de consulta já normalizado
--- @return table<integer, table<string, {kind:string, sim:number, matched:string}>>
function ExactMatcher.match(index, token)
    local candidates = {}

    local function record(indexedToken, kind, sim)
        local postings = index:postingsFor(indexedToken)
        if not postings then
            return
        end
        for itemId, fields in pairs(postings) do
            local byField = candidates[itemId]
            if not byField then
                byField = {}
                candidates[itemId] = byField
            end
            for field in pairs(fields) do
                local existing = byField[field]
                if not existing or sim > existing.sim then
                    byField[field] = { kind = kind, sim = sim, matched = indexedToken }
                end
            end
        end
    end

    record(token, "exact", 1.0)

    if #token >= 2 then
        local prefixKey = token:sub(1, math.min(6, #token))
        for _, indexedToken in ipairs(index:tokensWithPrefix(prefixKey)) do
            if indexedToken ~= token and indexedToken:sub(1, #token) == token then
                local sim = math.max(0.5, #token / #indexedToken)
                record(indexedToken, "prefix", sim)
            end
        end
    end

    return candidates
end

NS.core.ExactMatcher = ExactMatcher
