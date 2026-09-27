-- Aplica os Constraint da Query e os filtros de UI (facets + faixas) sobre o
-- índice (§4.5 do spec). Constraints e filtros de UI são eliminatórios;
-- conceitos textuais (alias) NÃO são — esses só somam score/cobertura em
-- SearchScorer. Itens sem a spec da grandeza são excluídos sem erro.
local NS = SmartShopSearch
local Models = NS.core.Models
local FilterEngine = {}

local FACET_NAMES = { "category", "brand", "origin", "species" }

local function specsForQuantity(commonUnits, quantity)
    for _, q in ipairs((commonUnits and commonUnits.quantities) or {}) do
        if q.id == quantity then
            return q.specs
        end
    end
    return nil
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

--- @param index SearchIndex
--- @param query Query
--- @param ui UiFilters|nil
--- @param commonUnits table|nil  data/common/units.xml já parseado (quantities)
--- @return table<integer, boolean>|nil allowed  nil = sem restrição
--- @return table<integer, MatchReason[]> reasons
function FilterEngine.apply(index, query, ui, commonUnits)
    local sets = {}
    local reasons = {}

    for _, c in ipairs(query.constraints) do
        local specs = specsForQuantity(commonUnits, c.quantity)
        local allowed = {}
        for _, item in ipairs(index.items) do
            local specId, value = firstSpecValue(item, c.quantity, specs)
            if specId then
                local minOk = (c.min == nil) or (value >= c.min)
                local maxOk = (c.max == nil) or (value <= c.max)
                if minOk and maxOk then
                    allowed[item.id] = true
                    reasons[item.id] = reasons[item.id] or {}
                    local rangeText = string.format(
                        "%s ∈ [%s, %s]",
                        tostring(value),
                        c.min and string.format("%.1f", c.min) or "-inf",
                        c.max and string.format("%.1f", c.max) or "+inf"
                    )
                    reasons[item.id][#reasons[item.id] + 1] =
                        Models.reason("constraint", "spec." .. specId, query.raw, tostring(value), rangeText, 0)
                end
            end
        end
        sets[#sets + 1] = allowed
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

    return intersect(sets), reasons
end

NS.core.FilterEngine = FilterEngine
