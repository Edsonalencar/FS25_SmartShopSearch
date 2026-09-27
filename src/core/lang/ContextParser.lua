-- Reconhece frases de contexto de compatibilidade ("compatível com…", "para
-- este trator") e produz um QueryContext (L4 do spec; resolução em F8).
local NS = SmartShopSearch
local ContextParser = {}
ContextParser.__index = ContextParser

local function compilePhrases(phrases, normalizeFn)
    local out = {}
    for _, phrase in ipairs(phrases or {}) do
        local norm = normalizeFn(phrase)
        local tokens = {}
        for tok in norm:gmatch("%S+") do
            tokens[#tokens + 1] = tok
        end
        if #tokens > 0 then
            out[#out + 1] = tokens
        end
    end
    table.sort(out, function(a, b)
        return #a > #b
    end)
    return out
end

--- @param dataList table[]  lista de {compat=[frases], self=[frases]} por locale
--- @param normalizeFn fun(s:string):string
function ContextParser.new(dataList, normalizeFn)
    local compat, selfPhrases = {}, {}
    for _, d in ipairs(dataList or {}) do
        for _, p in ipairs(compilePhrases(d.compat, normalizeFn)) do
            compat[#compat + 1] = p
        end
        for _, p in ipairs(compilePhrases(d.self, normalizeFn)) do
            selfPhrases[#selfPhrases + 1] = p
        end
    end
    table.sort(compat, function(a, b)
        return #a > #b
    end)
    table.sort(selfPhrases, function(a, b)
        return #a > #b
    end)
    return setmetatable({ compat = compat, self = selfPhrases }, ContextParser)
end

local function matchAt(phraseTokens, tokens, pos)
    if pos + #phraseTokens - 1 > #tokens then
        return false
    end
    for k, word in ipairs(phraseTokens) do
        if tokens[pos + k - 1].text ~= word then
            return false
        end
    end
    return true
end

---@param tokens {text:string, s:integer, e:integer}[]
---@param i integer
---@return {kind:"compatibleWith", target:"selected"|"query", targetTerms:string[],
---span:integer[], consumed:integer}|nil
function ContextParser:parseAt(tokens, i)
    local compatLen = nil
    for _, phrase in ipairs(self.compat) do
        if matchAt(phrase, tokens, i) then
            compatLen = #phrase
            break
        end
    end
    if not compatLen then
        return nil
    end

    local pos = i + compatLen
    for _, phrase in ipairs(self.self) do
        if matchAt(phrase, tokens, pos) then
            local endPos = pos + #phrase - 1
            return {
                kind = "compatibleWith",
                target = "selected",
                targetTerms = {},
                span = { tokens[i].s, tokens[endPos].e },
                consumed = compatLen + #phrase,
            }
        end
    end

    -- sem frase "self": o restante da consulta vira targetTerms (busca por texto do alvo)
    local targetTerms = {}
    for k = pos, #tokens do
        targetTerms[#targetTerms + 1] = tokens[k].text
    end
    local lastIdx = math.max(pos - 1, i + compatLen - 1)
    return {
        kind = "compatibleWith",
        target = "query",
        targetTerms = targetTerms,
        span = { tokens[i].s, tokens[lastIdx].e },
        consumed = #tokens - i + 1,
    }
end

NS.core.ContextParser = ContextParser
