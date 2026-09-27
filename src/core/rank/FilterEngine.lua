-- Aplica os Constraint da Query e os filtros de UI (facets + faixas) sobre o
-- índice (§4.5 do spec). Constraints e filtros de UI são eliminatórios;
-- conceitos textuais (alias) NÃO são — esses só somam score/cobertura em
-- SearchScorer. Itens sem a spec da grandeza são excluídos sem erro.
local NS = SmartShopSearch
local Models = NS.core.Models
local FilterEngine = {}

local FACET_NAMES = { "category", "brand", "origin", "species" }

local function quantityDef(commonUnits, quantity)
    for _, q in ipairs((commonUnits and commonUnits.quantities) or {}) do
        if q.id == quantity then
            return q
        end
    end
    return nil
end

-- Rótulo de exibição dos aliases de unidade (os ids de units.xml são
-- normalizados: "kw", "kmh", "m3"). Sem entrada, exibe o próprio alias.
local UNIT_LABEL = { kw = "kW", l = "L", lt = "L", kmh = "km/h", m3 = "m³" }

local function unitLabel(alias)
    return UNIT_LABEL[alias] or alias
end

--- Número curto para o texto do motivo: inteiro a partir de 100 ou quando
--- já é inteiro, senão uma casa decimal.
local function fmtNumber(v)
    if math.abs(v) >= 100 or v == math.floor(v) then
        return string.format("%.0f", v)
    end
    return string.format("%.1f", v)
end

--- Texto do valor do item no motivo de constraint: unidade canônica e, se a
--- consulta usou outra unidade, a conversão inversa (spec F4: "184 kW (250 cv)").
local function valueText(value, constraint, canonical)
    if constraint.quantity == "money" or not canonical then
        return fmtNumber(value)
    end
    local text = fmtNumber(value) .. " " .. unitLabel(canonical)
    local factor = constraint.factor
    if constraint.unit and constraint.unit ~= canonical and factor and factor > 0 and factor ~= 1 then
        text = text .. " (" .. fmtNumber(value / factor) .. " " .. unitLabel(constraint.unit) .. ")"
    end
    return text
end

--- Resolve, para um item e uma grandeza, a PRIMEIRA spec presente (L10):
--- @return string|nil specId, number|nil value
local function firstSpecValue(item, quantity, specs)
    if quantity == "money" then
        if item.price ~= nil then
            return "price", item.price
        end
        return nil
    end
    for _, specId in ipairs(specs or {}) do
        local spec = item.specs[specId]
        if spec then
            return specId, spec.value
        end
    end
    return nil
end

local function intersect(sets)
    if #sets == 0 then
        return nil -- sem restrição alguma
    end
    local result = {}
    for id in pairs(sets[1]) do
        result[id] = true
    end
    for k = 2, #sets do
        local next_ = {}
        for id in pairs(result) do
            if sets[k][id] then
                next_[id] = true
            end
        end
        result = next_
    end
    return result
end

--- Itens que satisfazem uma constraint, respeitando L10 (o item é avaliado
--- só pela PRIMEIRA spec da grandeza que possui): busca binária em
--- `numeric[spec]` para cada spec da lista; um item achado pela spec k só vale
--- se não tiver nenhuma das specs 1..k-1. Sem alocação por item fora do
--- conjunto de saída (PRD §15).
local function constraintIds(index, c, specs)
    if c.quantity == "money" then
        return index:rangeIds("price", c.min, c.max)
    end
    local allowed = {}
    for k, specId in ipairs(specs or {}) do
        for itemId in pairs(index:rangeIds(specId, c.min, c.max)) do
            local shadowed = false
            if k > 1 then
                local itemSpecs = index.items[itemId].specs
                for j = 1, k - 1 do
                    if itemSpecs[specs[j]] then
                        shadowed = true
                        break
                    end
                end
            end
            if not shadowed then
                allowed[itemId] = true
            end
        end
    end
    return allowed
end

--- MatchReason das constraints para um item que passou pelos filtros. Gerado
--- sob demanda só para os resultados exibidos (SearchService), não para
--- todos os itens aprovados.
--- @param item IndexedItem
--- @param query Query
--- @param commonUnits table|nil
--- @return MatchReason[]
function FilterEngine.reasonsFor(item, query, commonUnits)
    local out = {}
    for _, c in ipairs(query.constraints or {}) do
        local def = quantityDef(commonUnits, c.quantity)
        local specId, value = firstSpecValue(item, c.quantity, def and def.specs)
        if specId then
            local rangeText = string.format(
                "%s ∈ [%s, %s]",
                valueText(value, c, def and def.canonical),
                c.min and string.format("%.1f", c.min) or "-inf",
                c.max and string.format("%.1f", c.max) or "+inf"
            )
            out[#out + 1] = Models.reason("constraint", "spec." .. specId, query.raw, tostring(value), rangeText, 0)
        end
    end
    return out
end

--- @param index SearchIndex
--- @param query Query
--- @param ui UiFilters|nil
--- @param commonUnits table|nil  data/common/units.xml já parseado (quantities)
--- @return table<integer, boolean>|nil allowed  nil = sem restrição
function FilterEngine.apply(index, query, ui, commonUnits)
    local sets = {}

    for _, c in ipairs(query.constraints) do
        local def = quantityDef(commonUnits, c.quantity)
        sets[#sets + 1] = constraintIds(index, c, def and def.specs)
    end

    if ui then
        for _, facetName in ipairs(FACET_NAMES) do
            local uiFilter = ui[facetName]
            if uiFilter and uiFilter.ids then
                local allowed = {}
                local facet = index.facets[facetName]
                if facet then
                    for _, key in ipairs(uiFilter.ids) do
                        local set = facet[key]
                        if set then
                            for itemId in pairs(set) do
                                allowed[itemId] = true
                            end
                        end
                    end
                end
                sets[#sets + 1] = allowed
            end
        end
        if ui.price then
            sets[#sets + 1] = index:rangeIds("price", ui.price.min, ui.price.max)
        end
        if ui.specs then
            for specId, range in pairs(ui.specs) do
                sets[#sets + 1] = index:rangeIds(specId, range.min, range.max)
            end
        end
    end

    return intersect(sets)
end

NS.core.FilterEngine = FilterEngine
