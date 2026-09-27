-- Registro spec -> {quantity, canonicalUnit}, construído a partir de
-- data/common/units.xml (cada <quantity specs="..."> lista as specs que
-- pertencem à grandeza). Uma nova spec é só uma entrada nos dados,
-- sem mudar código (RNF-006).
local NS = SmartShopSearch
local SpecRegistry = {}

---@param commonUnits {quantities: table[]}|nil  data/common/units.xml já parseado
---@return table<string, {quantity:string, canonicalUnit:string}>
function SpecRegistry.build(commonUnits)
    local registry = {}
    for _, q in ipairs((commonUnits and commonUnits.quantities) or {}) do
        for _, specId in ipairs(q.specs) do
            registry[specId] = { quantity = q.id, canonicalUnit = q.canonical }
        end
    end
    return registry
end

NS.core.SpecRegistry = SpecRegistry
