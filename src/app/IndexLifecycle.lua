-- Ciclo de vida do índice de busca (ADR-04): construção sob demanda,
-- fatiada por orçamento de frame, invalidada por assinatura do catálogo
-- (contagem + hash de xmlFilename).
--
-- Depois do build primário, uma segunda fase opcional (F6, PRD §9.2) lê specs
-- secundárias do XML de cada item, só para as specs com cobertura primária
-- abaixo de SECONDARY_COVERAGE, e sempre fatiada: só avança por `ensure` com
-- orçamento (nunca pelo `ensure(nil)` de uma busca), e aplica tudo de uma vez
-- ao fim, para o índice nunca ficar num estado intermediário.
local NS = SmartShopSearch
local Signature = NS.core.Signature

local IndexLifecycle = {}
IndexLifecycle.__index = IndexLifecycle

local SECONDARY_COVERAGE = 0.8

---@param diagnostics table  app/Diagnostics
---@param deps {catalog:table, builder:table, clock:table|nil, specIds:string[]|nil}
--- builder: core/index/IndexBuilder. catalog pode expor `secondarySpecsFor(item)`
--- (adapters/StoreCatalogSource); com `specIds`, liga a fase secundária.
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
        secondary = nil,
    }, IndexLifecycle)
end

local function countKeys(t)
    local n = 0
    for _ in pairs(t) do
        n = n + 1
    end
    return n
end

--- Prepara a fase secundária, se o catálogo a suportar e alguma spec tiver
--- cobertura primária baixa.
function IndexLifecycle:_planSecondary()
    self.secondary = nil
    local catalog, specIds = self.deps.catalog, self.deps.specIds
    if not (catalog and type(catalog.secondarySpecsFor) == "function" and specIds and #specIds > 0) then
        return
    end
    local coverage = NS.core.IndexBuilder.specCoverage(self.index, specIds)
    if self.diagnostics then
        self.diagnostics.specCoverage = coverage
    end
    local lowSpecs = {}
    for _, specId in ipairs(specIds) do
        if coverage[specId] < SECONDARY_COVERAGE then
            lowSpecs[#lowSpecs + 1] = specId
        end
    end
    if #lowSpecs > 0 and #self.index.items > 0 then
        self.secondary = { cursor = 1, lowSpecs = lowSpecs, additions = {}, reads = 0 }
    end
end

--- Avança a fase secundária até estourar `budgetSec` (sem clock, faz tudo).
--- @return boolean done
function IndexLifecycle:stepSecondary(budgetSec)
    local sec = self.secondary
    if not sec then
        return true
    end
    local clock = self.deps.clock
    local startTime = (budgetSec and clock) and clock:now() or nil
    local items = self.index.items
    while sec.cursor <= #items do
        local item = items[sec.cursor]
        local missing = false
        for _, specId in ipairs(sec.lowSpecs) do
            if not item.specs[specId] then
                missing = true
                break
            end
        end
        if missing then
            sec.reads = sec.reads + 1
            local ok, values = pcall(self.deps.catalog.secondarySpecsFor, self.deps.catalog, item)
            if ok and type(values) == "table" then
                local wanted = nil
                for _, specId in ipairs(sec.lowSpecs) do
                    if values[specId] ~= nil and not item.specs[specId] then
                        wanted = wanted or {}
                        wanted[specId] = values[specId]
                    end
                end
                sec.additions[item.id] = wanted
            elseif not ok and self.diagnostics then
                self.diagnostics:recordSkip("secondary-error", 1)
            end
        end
        sec.cursor = sec.cursor + 1
        if startTime and clock:now() - startTime >= budgetSec then
            return false
        end
    end

    local added = NS.core.IndexBuilder.applySecondary(self.index, sec.additions)
    if self.diagnostics then
        self.diagnostics.secondaryReads = sec.reads
        self.diagnostics.secondaryAdded = added
        self.diagnostics.specCoverage = NS.core.IndexBuilder.specCoverage(self.index, self.deps.specIds)
    end
    self.secondary = nil
    return true
end

--- @param budgetSec number|nil  nil = constrói tudo de uma vez (e não mexe na fase secundária)
--- @return boolean ready  true quando o índice está pronto para uso
function IndexLifecycle:ensure(budgetSec)
    if not (self.deps.catalog and self.deps.builder) then
        return self.index ~= nil
    end

    local rawItems = self.deps.catalog:items()
    local sig = Signature.of(rawItems)

    if self.index and self.signature == sig then
        -- catálogo não mudou desde a última construção
        if self.secondary and budgetSec then
            self:stepSecondary(budgetSec)
        end
        return true
    end

    if not self.buildState or self.buildingSignature ~= sig then
        self.buildState = self.deps.builder:begin(rawItems)
        self.buildingSignature = sig
        self.buildStartTime = self.deps.clock and self.deps.clock:now() or nil
        self.buildMemBefore = collectgarbage("count")
        self.secondary = nil
    end

    return self:_stepBuild(budgetSec)
end

--- Avança o build primário em andamento; ao terminar, publica o índice.
--- @return boolean done
function IndexLifecycle:_stepBuild(budgetSec)
    local done = self.deps.builder:step(self.buildState, budgetSec, self.deps.clock)
    if done then
        self.index = self.buildState.index
        self.signature = self.buildingSignature

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
        self:_planSecondary()
    end
    return done
end

--- Continua o trabalho já em andamento (build primário ou fase secundária)
--- sem reler o catálogo nem recalcular a assinatura — para o tick por frame
--- da loja aberta (ShopGuiAdapter.onFrame). Sem trabalho pendente, não faz nada.
--- @return boolean busy  true se ainda resta trabalho
function IndexLifecycle:stepPending(budgetSec)
    if self.buildState then
        self:_stepBuild(budgetSec)
    elseif self.secondary then
        self:stepSecondary(budgetSec)
    end
    return self:isBusy()
end

--- true enquanto há construção primária em andamento ou fase secundária
--- pendente (indicador `sss_indexing` da GUI).
function IndexLifecycle:isBusy()
    return self.buildState ~= nil or self.secondary ~= nil
end

--- Força reconstrução completa (comando de console sssReindex, QM-09). A fase
--- secundária fica pendente e continua fatiada, como num build normal.
function IndexLifecycle:forceRebuild()
    self.index = nil
    self.signature = nil
    self.buildState = nil
    self.buildingSignature = nil
    self.secondary = nil
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
    self.secondary = nil
end

NS.app.IndexLifecycle = IndexLifecycle
