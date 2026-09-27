-- Interpreta comparadores (gt/gte/lt/lte/approx), intervalos ("entre A e B")
-- e números isolados seguidos de unidade (§4.2 do spec). Devolve um
-- Constraint{quantity, op, min, max, consumed} — `quantity` pode ficar nil
-- quando não há moeda/unidade explícita; a regra L9 (QueryParser) decide.
local NS = SmartShopSearch
local ComparatorParser = {}
ComparatorParser.__index = ComparatorParser

--- Divide um padrão bruto ("entre {a} e {b}") em uma lista de elementos
--- {kind="literal", text=...} / {kind="placeholder", name="a"|"b"}, com os
--- trechos literais já normalizados e tokenizados (a mesma normalização da
--- consulta, para casar token a token).
local function compileTemplate(raw, normalizeFn)
    local segments = {}
    local pos = 1
    while true do
        local s, e = raw:find("%b{}", pos)
        if not s then
            segments[#segments + 1] = { kind = "literal", text = raw:sub(pos) }
            break
        end
        if s > pos then
            segments[#segments + 1] = { kind = "literal", text = raw:sub(pos, s - 1) }
        end
        segments[#segments + 1] = { kind = "placeholder", name = raw:sub(s + 1, e - 1) }
        pos = e + 1
    end

    local pattern = {}
    for _, seg in ipairs(segments) do
        if seg.kind == "literal" then
            local norm = normalizeFn(seg.text)
            for tok in norm:gmatch("%S+") do
                pattern[#pattern + 1] = { kind = "literal", text = tok }
            end
        else
            pattern[#pattern + 1] = { kind = "placeholder", name = seg.name }
        end
    end
    return pattern
end

---@param dataList table[]  lista de {ops={id=[patterns]}, range=[patterns]} por locale
---@param numberParser table
---@param unitParser table
---@param normalizeFn fun(s:string):string
function ComparatorParser.new(dataList, numberParser, unitParser, normalizeFn)
    local opPatterns = {} -- lista de {op=id, pattern={...literais...}}, maior primeiro
    local rangePatterns = {} -- lista de pattern (com placeholders a/b), maior primeiro
    local seenOpText, seenRangeText = {}, {}

    for _, d in ipairs(dataList or {}) do
        for opId, phrases in pairs(d.ops or {}) do
            for _, phrase in ipairs(phrases) do
                if not seenOpText[opId .. "|" .. phrase] then
                    seenOpText[opId .. "|" .. phrase] = true
                    local pattern = compileTemplate(phrase, normalizeFn)
                    -- Símbolos puros (">", "<", "~") normalizam para nada (só
                    -- pontuação) e produziriam um padrão vazio que "casaria"
                    -- em qualquer posição — nunca registra um padrão vazio.
                    if #pattern > 0 then
                        opPatterns[#opPatterns + 1] = { op = opId, pattern = pattern }
                    end
                end
            end
        end
        for _, phrase in ipairs(d.range or {}) do
            if not seenRangeText[phrase] then
                seenRangeText[phrase] = true
                rangePatterns[#rangePatterns + 1] = compileTemplate(phrase, normalizeFn)
            end
        end
    end

    table.sort(opPatterns, function(a, b)
        return #a.pattern > #b.pattern
    end)
    table.sort(rangePatterns, function(a, b)
        return #a > #b
    end)

    return setmetatable({
        opPatterns = opPatterns,
        rangePatterns = rangePatterns,
        numberParser = numberParser,
        unitParser = unitParser,
    }, ComparatorParser)
end

--- Tenta casar uma unidade (ou moeda) a partir de `pos`; devolve
--- {quantity, factor, consumed} ou nil.
function ComparatorParser:_tryUnit(tokens, pos)
    local moneyMatch = self.unitParser:parseMoneyAt(tokens, pos)
    if moneyMatch then
        return { quantity = "money", factor = 1, consumed = moneyMatch.consumed }
    end
    return self.unitParser:parseAt(tokens, pos)
end

--- @return table|nil  {quantity, op="between", min, max, consumed, usedMultiplier, rawMagnitude}
function ComparatorParser:_tryRange(pattern, tokens, i)
    local pos = i
    local aVal, bVal, usedMultiplier = nil, nil, false
    for _, el in ipairs(pattern) do
        if el.kind == "literal" then
            if not tokens[pos] or tokens[pos].text ~= el.text then
                return nil
            end
            pos = pos + 1
        else
            local numResult = self.numberParser:parseAt(tokens, pos)
            if not numResult then
                return nil
            end
            if el.name == "a" then
                aVal = numResult.value
            else
                bVal = numResult.value
            end
            usedMultiplier = usedMultiplier or numResult.usedMultiplier
            pos = pos + numResult.consumed
        end
    end
    if aVal == nil or bVal == nil then
        return nil
    end

    local quantity, factor = nil, 1
    local unitMatch = self:_tryUnit(tokens, pos)
    if unitMatch then
        quantity, factor = unitMatch.quantity, unitMatch.factor
        pos = pos + unitMatch.consumed
    end

    local min, max = aVal * factor, bVal * factor
    if min > max then
        min, max = max, min
    end
    return {
        quantity = quantity,
        op = "between",
        min = min,
        max = max,
        consumed = pos - i,
        usedMultiplier = usedMultiplier,
        rawMagnitude = math.max(math.abs(aVal), math.abs(bVal)),
    }
end

--- @return table|nil  {quantity, op, min, max, consumed, usedMultiplier, rawMagnitude}
function ComparatorParser:_tryOp(entry, tokens, i)
    local pos = i
    for _, litTok in ipairs(entry.pattern) do
        if not tokens[pos] or tokens[pos].text ~= litTok.text then
            return nil
        end
        pos = pos + 1
    end

    local quantity, factor = nil, 1
    local moneyMatch = self.unitParser:parseMoneyAt(tokens, pos)
    if moneyMatch then
        quantity, factor = "money", 1
        pos = pos + moneyMatch.consumed
    end

    local numResult = self.numberParser:parseAt(tokens, pos)
    if not numResult then
        return nil
    end
    pos = pos + numResult.consumed

    if not quantity then
        local unitMatch = self.unitParser:parseAt(tokens, pos)
        if unitMatch then
            quantity, factor = unitMatch.quantity, unitMatch.factor
            pos = pos + unitMatch.consumed
        end
    end

    local value = numResult.value * factor
    local min, max
    if entry.op == "gt" or entry.op == "gte" then
        min = value
    elseif entry.op == "lt" or entry.op == "lte" then
        max = value
    elseif entry.op == "approx" then
        min, max = value * 0.9, value * 1.1
    end

    return {
        quantity = quantity,
        op = entry.op,
        min = min,
        max = max,
        consumed = pos - i,
        usedMultiplier = numResult.usedMultiplier,
        rawMagnitude = math.abs(numResult.value),
    }
end

--- Número isolado seguido de unidade (ou precedido de moeda): vira um
--- "eq" com tolerância de ±5% (RF-027; ex. "200 cv" -> [190,210] cv antes
--- da conversão, ou já convertido para a unidade canônica).
--- @return table|nil
function ComparatorParser:_tryStandalone(tokens, i)
    local pos = i
    local quantity, factor = nil, 1
    local moneyMatch = self.unitParser:parseMoneyAt(tokens, pos)
    if moneyMatch then
        quantity, factor = "money", 1
        pos = pos + moneyMatch.consumed
    end

    local numResult = self.numberParser:parseAt(tokens, pos)
    if not numResult then
        return nil
    end
    pos = pos + numResult.consumed

    if not quantity then
        local unitMatch = self.unitParser:parseAt(tokens, pos)
        if not unitMatch then
            return nil -- número isolado sem unidade/moeda não é constraint aqui
        end
        quantity, factor = unitMatch.quantity, unitMatch.factor
        pos = pos + unitMatch.consumed
    end

    local value = numResult.value * factor
    return {
        quantity = quantity,
        op = "between",
        min = value * 0.95,
        max = value * 1.05,
        consumed = pos - i,
        usedMultiplier = numResult.usedMultiplier,
        rawMagnitude = math.abs(numResult.value),
        approxTolerance = true,
    }
end

---@param tokens {text:string, s:integer, e:integer}[]
---@param i integer
---@return table|nil Constraint (sem span; o QueryParser preenche)
function ComparatorParser:parseAt(tokens, i)
    for _, pattern in ipairs(self.rangePatterns) do
        local result = self:_tryRange(pattern, tokens, i)
        if result then
            return result
        end
    end
    for _, entry in ipairs(self.opPatterns) do
        local result = self:_tryOp(entry, tokens, i)
        if result then
            return result
        end
    end
    return self:_tryStandalone(tokens, i)
end

NS.core.ComparatorParser = ComparatorParser
