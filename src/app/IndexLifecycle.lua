-- Ciclo de vida do índice de busca (ADR-04): construção sob demanda,
-- fatiada por orçamento de frame, invalidada por assinatura do catálogo
-- (contagem + hash de xmlFilename).
local NS = SmartShopSearch
local Signature = NS.core.Signature

local IndexLifecycle = {}
IndexLifecycle.__index = IndexLifecycle

---@param diagnostics table  app/Diagnostics
---@param deps {catalog:table, builder:table, clock:table|nil}  -- builder: core/index/IndexBuilder
function IndexLifecycle.new(diagnostics, deps)
    return setmetatable({
        diagnostics = diagnostics,
        deps = deps or {},
        index = nil,
        signature = nil,
        buildState = nil,
        buildingSignature = nil,
        buildStartTime = nil,
        buildMemBefore = nil,
    }, IndexLifecycle)
end

local function countKeys(t)
    local n = 0
    for _ in pairs(t) do
        n = n + 1
    end
    return n
end

--- @param budgetSec number|nil  nil = constrói tudo de uma vez
--- @return boolean ready  true quando o índice está pronto para uso
function IndexLifecycle:ensure(budgetSec)
    if not (self.deps.catalog and self.deps.builder) then
        return self.index ~= nil
    end

    local rawItems = self.deps.catalog:items()
    local sig = Signature.of(rawItems)

    if self.index and self.signature == sig then
        return true -- catálogo não mudou desde a última construção
    end

    if not self.buildState or self.buildingSignature ~= sig then
        self.buildState = self.deps.builder:begin(rawItems)
        self.buildingSignature = sig
        self.buildStartTime = self.deps.clock and self.deps.clock:now() or nil
        self.buildMemBefore = collectgarbage("count")
    end

    local done = self.deps.builder:step(self.buildState, budgetSec, self.deps.clock)
    if done then
        self.index = self.buildState.index
        self.signature = sig

        local elapsedMs = 0
        if self.deps.clock and self.buildStartTime then
            elapsedMs = (self.deps.clock:now() - self.buildStartTime) * 1000
        end
        if self.diagnostics then
            local memAfter = collectgarbage("count")
            local memDeltaKb = memAfter - (self.buildMemBefore or memAfter)
            self.diagnostics:recordBuild(elapsedMs, #self.index.items, countKeys(self.index.vocabulary), memDeltaKb)
            for reason, n in pairs(self.index.skipped or {}) do
                self.diagnostics:recordSkip(reason, n)
            end
        end

        self.buildState = nil
        self.buildingSignature = nil
        self.buildStartTime = nil
        self.buildMemBefore = nil
    end
    return done
end

--- Força reconstrução completa (comando de console sssReindex, QM-09).
function IndexLifecycle:forceRebuild()
    self.index = nil
    self.signature = nil
    self.buildState = nil
    self.buildingSignature = nil
    self:ensure(nil)
end

function IndexLifecycle:itemCount()
    return (self.index and self.index.items and #self.index.items) or 0
end

function IndexLifecycle:release()
    self.index = nil
    self.signature = nil
    self.buildState = nil
    self.buildingSignature = nil
    self.buildStartTime = nil
end

NS.app.IndexLifecycle = IndexLifecycle
