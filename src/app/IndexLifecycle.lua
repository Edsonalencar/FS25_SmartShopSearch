-- Ciclo de vida do índice de busca (ADR-04): construção sob demanda, fatiada,
-- invalidação por assinatura do catálogo. Stub na F1 (sem catálogo real
-- ainda); implementação completa na F2 (ver `ensure`).
local NS = SmartShopSearch
local IndexLifecycle = {}
IndexLifecycle.__index = IndexLifecycle

function IndexLifecycle.new(diagnostics, deps)
    return setmetatable({
        diagnostics = diagnostics,
        deps = deps or {},
        index = nil,
        signature = nil,
        buildState = nil,
    }, IndexLifecycle)
end

---@param budgetSec number|nil
---@return boolean done
function IndexLifecycle:ensure(budgetSec) -- luacheck: ignore 212
    return true -- F2: builder real via core/index/IndexBuilder
end

function IndexLifecycle:forceRebuild()
    self.index = nil
    self.signature = nil
    self:ensure()
end

function IndexLifecycle:itemCount()
    return (self.index and self.index.items and #self.index.items) or 0
end

function IndexLifecycle:release()
    self.index = nil
    self.signature = nil
    self.buildState = nil
end

NS.app.IndexLifecycle = IndexLifecycle
