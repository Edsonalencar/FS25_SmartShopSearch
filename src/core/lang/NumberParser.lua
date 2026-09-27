-- Interpreta números (inteiros, com separadores localizados, por extenso e
-- com multiplicador) a partir da posição `i` de uma lista de tokens já
-- normalizados (§4.2 do spec).
local NS = SmartShopSearch
local NumberParser = {}
NumberParser.__index = NumberParser

--- @param dataList table[]  lista de {decimal, thousands, multipliers, spelled}
--- por locale (idioma do jogo primeiro, depois "en" — decimal/thousands vêm
--- do primeiro; multipliers/spelled são mesclados, primeira ocorrência vence).
function NumberParser.new(dataList)
    local decimal, thousands = ".", ","
    if dataList and dataList[1] then
        decimal = dataList[1].decimal or decimal
        thousands = dataList[1].thousands or thousands
    end
    local multipliers, spelled = {}, {}
    for _, d in ipairs(dataList or {}) do
        for word, factor in pairs(d.multipliers or {}) do
            if multipliers[word] == nil then
                multipliers[word] = factor
            end
        end
        for word, value in pairs(d.spelled or {}) do
            if spelled[word] == nil then
                spelled[word] = value
            end
        end
    end
    return setmetatable(
        { decimal = decimal, thousands = thousands, multipliers = multipliers, spelled = spelled },
        NumberParser
    )
end

--- Interpreta um único token numérico com separadores localizados.
--- Regras: separador igual ao decimal, ou grupo final sem 3 dígitos após o
--- separador de milhar, é tratado como decimal (tolerância); os demais
--- grupos precisam ter exatamente 3 dígitos para contar como milhar.
--- @return number|nil
function NumberParser:parseDigitToken(token)
    local negative = false
    if token:sub(1, 1) == "-" then
        negative = true
        token = token:sub(2)
    end
    if token == "" or not token:find("%d") then
        return nil
    end

    local groups, seps = {}, {}
    local cur = ""
    for k = 1, #token do
        local c = token:sub(k, k)
        if c == self.decimal or c == self.thousands then
            groups[#groups + 1] = cur
            seps[#seps + 1] = c
            cur = ""
        elseif c:match("%d") then
            cur = cur .. c
        else
            return nil -- caractere não numérico/separador -> não é um número válido
        end
    end
    groups[#groups + 1] = cur

    local value
    if #groups == 1 then
        if groups[1] == "" then
            return nil
        end
        value = tonumber(groups[1])
    else
        local lastSep, lastGroup = seps[#seps], groups[#groups]
        local isDecimal = (lastSep == self.decimal) or (#lastGroup ~= 3)
        if isDecimal then
            if lastGroup == "" then
                return nil
            end
            local intPart = table.concat(groups, "", 1, #groups - 1)
            if intPart == "" then
                return nil
            end
            value = tonumber(intPart .. "." .. lastGroup)
        else
            for k = 2, #groups do
                if #groups[k] ~= 3 then
                    return nil -- grupo de milhar malformado
                end
            end
            value = tonumber(table.concat(groups))
        end
    end

    if value == nil then
        return nil
    end
    return negative and -value or value
end

--- @param tokens {text:string, s:integer, e:integer}[]
--- @param i integer
--- @return {value:number, consumed:integer, usedMultiplier:boolean}|nil
function NumberParser:parseAt(tokens, i)
    if not tokens[i] then
        return nil
    end
    local tok = tokens[i].text

    -- 1. numeral por extenso
    if self.spelled[tok] then
        return { value = self.spelled[tok], consumed = 1, usedMultiplier = false }
    end

    -- 2. dígitos com separadores
    local value = self:parseDigitToken(tok)
    if not value then
        return nil -- token não é um número válido (RF-036: segue como termo)
    end

    -- 3. multiplicador no token seguinte ("150 mil", "1,5 mi")
    local nextTok = tokens[i + 1]
    if nextTok and self.multipliers[nextTok.text] then
        return { value = value * self.multipliers[nextTok.text], consumed = 2, usedMultiplier = true }
    end

    return { value = value, consumed = 1, usedMultiplier = false }
end

NS.core.NumberParser = NumberParser
