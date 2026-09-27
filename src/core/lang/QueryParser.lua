-- Orquestra a varredura esquerda->direita da consulta (§4.2/§22 do spec):
-- ContextParser -> ComparatorParser (número/unidade/moeda) -> AliasResolver
-- -> termo pendente. Pendentes viram QueryTerm após remover stopwords.
local NS = SmartShopSearch
local Tokenizer = NS.core.Tokenizer
local Utf8 = NS.core.Utf8
local FuzzyMatcher = NS.core.FuzzyMatcher
local QueryParser = {}
QueryParser.__index = QueryParser

--- @param deps {normalizer:table, contextParser:table|nil, comparatorParser:table|nil,
--- aliasResolver:table|nil, stopwords:table|nil}  stopwords: set {[word]=true}
function QueryParser.new(deps)
    return setmetatable(deps or {}, QueryParser)
end

local function emptyQuery(text, locale)
    return {
        raw = text,
        terms = {},
        concepts = {},
        constraints = {},
        context = nil,
        locale = locale or "en",
        warnings = {},
    }
end

--- Aplica a regra L9: constraint sem quantidade vira "money" se usou
--- multiplicador ou o valor bruto é >= 1000; senão é descartada (os tokens
--- voltam a poder virar termo/conceito nas próximas fases do scan).
local function applyL9(constraint)
    if constraint.quantity then
        return constraint
    end
    if constraint.usedMultiplier or (constraint.rawMagnitude and constraint.rawMagnitude >= 1000) then
        constraint.quantity = "money"
        return constraint
    end
    return nil
end

---@param text string
---@param locale string|nil
---@return Query
function QueryParser:parse(text, locale)
    local query = emptyQuery(text, locale)
    if type(text) ~= "string" then
        return query
    end
    local norm = self.normalizer:normalize(text)
    if norm == "" then
        return query
    end
    local tokens = Tokenizer.tokenize(norm)
    local pending = {}

    local i = 1
    while i <= #tokens do
        local consumed = nil

        local ctx = self.contextParser and self.contextParser:parseAt(tokens, i)
        if ctx then
            if query.context then
                query.warnings[#query.warnings + 1] = "contexto duplicado ignorado"
            else
                query.context = ctx
            end
            consumed = ctx.consumed
        end

        if not consumed and self.comparatorParser then
            local constraint = self.comparatorParser:parseAt(tokens, i)
            if constraint then
                constraint = applyL9(constraint)
                if constraint then
                    constraint.span = { tokens[i].s, tokens[i + constraint.consumed - 1].e }
                    query.constraints[#query.constraints + 1] = constraint
                    consumed = constraint.consumed
                else
                    query.warnings[#query.warnings + 1] = "numero sem unidade descartado"
                end
            end
        end

        if not consumed and self.aliasResolver then
            local resolved = self.aliasResolver:resolveAt(tokens, i, true)
            if resolved then
                local parts = {}
                for k = 0, resolved.consumed - 1 do
                    parts[#parts + 1] = tokens[i + k].text
                end
                query.concepts[#query.concepts + 1] = {
                    kind = resolved.kind,
                    value = resolved.id,
                    confidence = resolved.confidence,
                    span = resolved.span,
                    queryText = table.concat(parts, " "),
                    consumed = resolved.consumed,
                }
                consumed = resolved.consumed
            end
        end

        if not consumed then
            pending[#pending + 1] = i
            consumed = 1
        end

        i = i + consumed
    end

    -- Contador diagnóstico (usado pela propriedade de conservação de tokens
    -- em tests/prop/parser_prop_spec.lua): quantos pendentes foram descartados
    -- por serem stopword, em vez de virar QueryTerm.
    query.stopwordsDropped = 0
    for _, idx in ipairs(pending) do
        local tok = tokens[idx]
        if self.stopwords and self.stopwords[tok.text] then
            query.stopwordsDropped = query.stopwordsDropped + 1
        else
            query.terms[#query.terms + 1] = {
                text = tok.text,
                span = { tok.s, tok.e },
                fuzzyMax = FuzzyMatcher.maxDistFor(Utf8.len(tok.text)),
            }
        end
    end

    local seenQuantities = {}
    for _, c in ipairs(query.constraints) do
        if seenQuantities[c.quantity] then
            query.warnings[#query.warnings + 1] = "constraint duplicada: " .. tostring(c.quantity)
        end
        seenQuantities[c.quantity] = true
    end

    return query
end

NS.core.QueryParser = QueryParser
