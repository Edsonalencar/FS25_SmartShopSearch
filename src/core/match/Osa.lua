-- Distância Damerau-Levenshtein restrita (OSA: optimal string alignment),
-- com limite de distância e early exit (ADR-05), em bytes.
local NS = SmartShopSearch
local Osa = {}
local byte, abs = string.byte, math.abs

function Osa.distance(a, b, max)
    local la, lb = #a, #b
    if a == b then
        return 0
    end
    if abs(la - lb) > max then
        return max + 1
    end
    local prev2, prev, cur = {}, {}, {}
    for j = 0, lb do
        prev[j] = j
    end
    for i = 1, la do
        cur[0] = i
        local rowMin = i
        local ai, ap = byte(a, i), (i > 1) and byte(a, i - 1) or nil
        for j = 1, lb do
            local bj = byte(b, j)
            local v = prev[j] + 1
            local t = cur[j - 1] + 1
            if t < v then
                v = t
            end
            t = prev[j - 1] + ((ai == bj) and 0 or 1)
            if t < v then
                v = t
            end
            if ap and j > 1 and ai == byte(b, j - 1) and ap == bj then
                t = prev2[j - 2] + 1
                if t < v then
                    v = t
                end
            end
            cur[j] = v
            if v < rowMin then
                rowMin = v
            end
        end
        if rowMin > max then
            return max + 1
        end
        prev2, prev, cur = prev, cur, prev2
    end
    return prev[lb]
end

NS.core.Osa = Osa
