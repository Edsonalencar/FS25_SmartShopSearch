-- Tolerância a erro de digitação (RF-016..022, ADR-05) e fuzzy de frase
-- (ADR-14, L6). Só entra em ação quando o termo não teve hit exato (economia
-- de custo); termos com <=3 bytes usam só exato/prefixo (RF-022).
local NS = SmartShopSearch
local Osa = NS.core.Osa
local Utf8 = NS.core.Utf8
local Weights = NS.core.Weights
local FuzzyMatcher = {}

---@param len integer  Utf8.len do token/frase (sem espaços, no caso de frase)
---@return integer maxDist
function FuzzyMatcher.maxDistFor(len)
    for _, tier in ipairs(Weights.fuzzyMaxByLen) do
        if len <= tier.maxLen then
            return tier.dist
        end
    end
    return Weights.fuzzyMaxByLen[#Weights.fuzzyMaxByLen].dist
end

local function kindForDist(dist)
    if dist <= 1 then
        return "fuzzy1"
    end
    return "fuzzy2"
end
FuzzyMatcher.kindForDist = kindForDist

--- Candidatos fuzzy de um único token de consulta contra o vocabulário do
--- índice (postings). Mesmo formato de candidates que ExactMatcher.match.
---@param index SearchIndex
---@param token string
---@return table<integer, table<string, {kind:string, sim:number, matched:string, dist:integer, fuzzyMax:integer}>>
function FuzzyMatcher.matchToken(index, token)
    local candidates = {}
    local maxDist = FuzzyMatcher.maxDistFor(Utf8.len(token))
    if maxDist == 0 or not index.trigramIndex then
        return candidates
    end

    for _, indexedToken in ipairs(index.trigramIndex:candidates(token, maxDist)) do
        if indexedToken ~= token then
            local dist = Osa.distance(token, indexedToken, maxDist)
            if dist <= maxDist then
                local sim = 1 - dist / math.max(#token, #indexedToken)
                local kind = kindForDist(dist)
                local postings = index:postingsFor(indexedToken)
                if postings then
                    for itemId, fields in pairs(postings) do
                        local byField = candidates[itemId]
                        if not byField then
                            byField = {}
                            candidates[itemId] = byField
                        end
                        for field in pairs(fields) do
                            local existing = byField[field]
                            if not existing or sim > existing.sim then
                                byField[field] =
                                    { kind = kind, sim = sim, matched = indexedToken, dist = dist, fuzzyMax = maxDist }
                            end
                        end
                    end
                end
            end
        end
    end
    return candidates
end

--- Primitiva genérica de fuzzy de frase (ADR-14): tenta janelas de `maxWindow`
--- até 2 tokens a partir de `i`, a maior primeiro, e casa a frase unida por
--- espaço contra `trigramIndex` (que pode indexar frases de itens ou de
--- aliases — o chamador decide o que fazer com o texto casado).
---@param trigramIndex TrigramIndex
---@param tokens {text:string, s:integer, e:integer}[]
---@param i integer
---@param maxWindow integer  3 ou 2
---@return {matched:string, dist:integer, consumed:integer, sim:number, maxDist:integer}|nil
function FuzzyMatcher.matchPhraseWindow(trigramIndex, tokens, i, maxWindow)
    for w = maxWindow, 2, -1 do
        if i + w - 1 <= #tokens then
            local parts = {}
            for k = 0, w - 1 do
                parts[#parts + 1] = tokens[i + k].text
            end
            local phrase = table.concat(parts, " ")
            local lenNoSpaces = Utf8.len((phrase:gsub(" ", "")))
            local maxDist = FuzzyMatcher.maxDistFor(lenNoSpaces)
            if maxDist > 0 then
                local best, bestDist = nil, maxDist + 1
                for _, cand in ipairs(trigramIndex:candidates(phrase, maxDist)) do
                    local dist = Osa.distance(phrase, cand, maxDist)
                    if dist < bestDist then
                        bestDist, best = dist, cand
                    end
                end
                if best and bestDist <= maxDist then
                    local sim = 1 - bestDist / math.max(#phrase, #best)
                    return { matched = best, dist = bestDist, consumed = w, sim = sim, maxDist = maxDist }
                end
            end
        end
    end
    return nil
end

--- Fuzzy de frase contra os textos multi-palavra dos itens (ADR-14:
--- `SearchIndex.phrases`, de brand/category/mod — ex. títulos de mod). Só
--- tenta janelas de 2–3 termos consecutivos que contenham ao menos um termo
--- sem hit exato (`needsHelp[i] = true`), para não mudar o ranking de
--- consultas que já casam termo a termo. A janela vencedora
--- consome os termos (não se sobrepõe à próxima).
---@param index SearchIndex
---@param terms {text:string}[]  QueryTerm[]
---@param needsHelp table<integer, boolean>
---@return {first:integer, consumed:integer, matched:string, dist:integer, sim:number, maxDist:integer}[]
function FuzzyMatcher.matchItemPhrases(index, terms, needsHelp)
    local out = {}
    if not index.phraseTrigram then
        return out
    end
    local i = 1
    while i < #terms do
        local m = nil
        for k = i, math.min(i + 2, #terms) do
            if needsHelp[k] then
                m = FuzzyMatcher.matchPhraseWindow(index.phraseTrigram, terms, i, 3)
                break
            end
        end
        local helps = false
        if m then
            for k = i, i + m.consumed - 1 do
                if needsHelp[k] then
                    helps = true
                end
            end
        end
        if helps then
            out[#out + 1] = {
                first = i,
                consumed = m.consumed,
                matched = m.matched,
                dist = m.dist,
                sim = m.sim,
                maxDist = m.maxDist,
            }
            i = i + m.consumed
        else
            i = i + 1
        end
    end
    return out
end

--- Itens cujo campo (brand/category/mod) normalizado é exatamente `phrase`,
--- achados pelas postings do primeiro token da frase.
---@param index SearchIndex
---@param phrase string
---@return table<integer, table<string, boolean>>  itemId -> {campo=true}
function FuzzyMatcher.itemsWithPhrase(index, phrase)
    local out = {}
    local phraseFields = index.phrases and index.phrases[phrase]
    local first = phrase:match("^[^ ]+")
    local postings = first and index:postingsFor(first)
    if not (phraseFields and postings) then
        return out
    end
    for itemId in pairs(postings) do
        local itemFields = index.items[itemId].fields
        for field in pairs(phraseFields) do
            local f = itemFields[field]
            if f and f.norm == phrase then
                out[itemId] = out[itemId] or {}
                out[itemId][field] = true
            end
        end
    end
    return out
end

NS.core.FuzzyMatcher = FuzzyMatcher
