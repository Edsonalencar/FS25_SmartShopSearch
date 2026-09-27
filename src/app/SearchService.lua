-- Orquestra o motor de busca (core/) sobre as portas injetadas. Stub na F1;
-- implementação real a partir da F2 (texto/índice) e completada nas F3/F4
-- (fuzzy, parser, filtros).
local NS = SmartShopSearch
local SearchService = {}
SearchService.__index = SearchService

---@param deps {catalog:table, logger:table, clock:table, data:table, settings:table}
function SearchService.new(deps)
    return setmetatable({ deps = deps or {} }, SearchService)
end

---@param budgetSec number|nil
---@return boolean ready
function SearchService:ensureIndex(budgetSec) -- luacheck: ignore 212
    return true -- F2
end

---@param text string
---@param ui table|nil
---@return table results
---@return table|nil query
function SearchService:search(text, ui) -- luacheck: ignore 212
    return {}, nil -- F2
end

NS.app.SearchService = SearchService
