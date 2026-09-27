-- Casa aliases de unidade (1 ou 2 tokens) contra as grandezas declaradas em
-- data/common/units.xml, com aliases localizados adicionais de
-- data/<lang>/units.xml (§4.2 do spec, L10).
local NS = SmartShopSearch
local UnitParser = {}
UnitParser.__index = UnitParser

---@param commonUnits {quantities: table[], protected: table[]}|nil  data/common/units.xml já parseado
---@param localizedDataList table[]  lista de {units: {alias, canonical}[]} por locale
function UnitParser.new(commonUnits, localizedDataList)
    local byAlias = {} -- alias -> {quantity, factor, canonical, alias}
    for _, q in ipairs((commonUnits and commonUnits.quantities) or {}) do
        for _, u in ipairs(q.units) do
            byAlias[u.alias] = { quantity = q.id, factor = u.factor, canonical = q.canonical, alias = u.alias }
        end
    end
    local localToCanonical = {}
    for _, d in ipairs(localizedDataList or {}) do
        for _, u in ipairs(d.units or {}) do
            if localToCanonical[u.alias] == nil then
                localToCanonical[u.alias] = u.canonical
            end
        end
    end
    return setmetatable({ byAlias = byAlias, localToCanonical = localToCanonical }, UnitParser)
end

--- @param word string  já normalizado
--- @return {quantity:string, factor:number, canonical:string, alias:string}|nil
function UnitParser:resolve(word)
    local info = self.byAlias[word]
    if info then
        return info
    end
    local canonical = self.localToCanonical[word]
    if canonical then
        return self.byAlias[canonical]
    end
    return nil
end

--- @param tokens {text:string}[]
--- @param i integer
--- `unit` é o alias comum da unidade digitada (ex. "cv", também para um
--- alias localizado como "cavalos"), usado para exibir o valor do item na
--- unidade da consulta (MatchReason de constraint).
--- @return {quantity:string, factor:number, unit:string, consumed:integer}|nil
function UnitParser:parseAt(tokens, i)
    if not tokens[i] then
        return nil
    end
    if tokens[i + 1] then
        local phrase = tokens[i].text .. " " .. tokens[i + 1].text
        local info = self:resolve(phrase)
        if info then
            return { quantity = info.quantity, factor = info.factor, unit = info.alias, consumed = 2 }
        end
    end
    local info = self:resolve(tokens[i].text)
    if info then
        return { quantity = info.quantity, factor = info.factor, unit = info.alias, consumed = 1 }
    end
    return nil
end

--- Caso específico de símbolo monetário (isolado como token próprio pelo
--- TextNormalizer, L8): "r$", "$", "€" antes do número.
--- @return {consumed:integer}|nil
function UnitParser:parseMoneyAt(tokens, i)
    if not tokens[i] then
        return nil
    end
    local info = self.byAlias[tokens[i].text]
    if info and info.quantity == "money" then
        return { consumed = 1 }
    end
    return nil
end

---@param value number
---@param unitMatch {factor:number}
---@return number
function UnitParser.toCanonical(value, unitMatch)
    return value * unitMatch.factor
end

NS.core.UnitParser = UnitParser
