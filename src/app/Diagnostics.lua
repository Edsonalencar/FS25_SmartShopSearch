-- Métricas internas do mod (PRD §13.3). Stub na F1; preenchido pelo
-- IndexBuilder/IndexLifecycle/SearchService a partir da F2.
local NS = SmartShopSearch
local Diagnostics = {}
Diagnostics.__index = Diagnostics

function Diagnostics.new()
    return setmetatable({
        buildTimeMs = 0,
        itemCount = 0,
        tokenCount = 0,
        memoryKb = 0,
        skipped = {}, -- reason -> count
        latencies = {}, -- anel das últimas 100 consultas (ms)
        specCoverage = {}, -- spec -> fração dos itens com valor (0..1)
        secondaryReads = 0, -- itens cujo XML foi lido na fase secundária (F6)
        secondaryAdded = 0, -- specs acrescentadas pela fase secundária
    }, Diagnostics)
end

function Diagnostics:recordBuild(timeMs, itemCount, tokenCount, memoryKb)
    self.buildTimeMs = timeMs
    self.itemCount = itemCount
    self.tokenCount = tokenCount
    self.memoryKb = memoryKb
end

function Diagnostics:recordSkip(reason, count)
    self.skipped[reason] = (self.skipped[reason] or 0) + (count or 1)
end

function Diagnostics:recordLatency(ms)
    local ring = self.latencies
    ring[#ring + 1] = ms
    if #ring > 100 then
        table.remove(ring, 1)
    end
end

--- Percentil simples sobre o anel de latências (0..1, ex. 0.5 = p50).
function Diagnostics:latencyPercentile(p)
    local ring = self.latencies
    if #ring == 0 then
        return 0
    end
    local sorted = {}
    for i, v in ipairs(ring) do
        sorted[i] = v
    end
    table.sort(sorted)
    local idx = math.max(1, math.min(#sorted, math.ceil(p * #sorted)))
    return sorted[idx]
end

NS.app.Diagnostics = Diagnostics
