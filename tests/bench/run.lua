#!/usr/bin/env lua
-- Benchmark do motor de busca (PRD §15): build do índice sobre um catálogo
-- sintético de 3000 itens e p50/p95 de consultas simples e compostas.
-- Uso:
--   lua tests/bench/run.lua --write-baseline   -- grava tests/bench/baseline.lua
--   lua tests/bench/run.lua --compare <arquivo> -- compara e falha se regredir > 20%
package.path = "./?.lua;" .. package.path

require("tests.support.load").load()
local NS = SmartShopSearch
local genCatalog = require("tests.bench.gen_catalog")
local FakeClock = require("tests.stubs.FakeClock")

local N_ITEMS = 3000
local N_QUERIES = 200
local TOLERANCE = 0.20
-- Piso absoluto (ms) abaixo do qual uma regressão relativa é ignorada: em
-- métricas de poucos milissegundos, ruído de GC/agendamento do SO produz
-- variações relativas grandes sem significado prático.
local ABS_FLOOR_MS = 1.0

local function percentile(list, p)
    local sorted = {}
    for i, v in ipairs(list) do
        sorted[i] = v
    end
    table.sort(sorted)
    if #sorted == 0 then
        return 0
    end
    local idx = math.max(1, math.min(#sorted, math.ceil(p * #sorted)))
    return sorted[idx]
end

local function measureMs(fn)
    local t0 = os.clock()
    fn()
    return (os.clock() - t0) * 1000
end

local function buildRng(seed)
    local state = seed
    return function(mod)
        state = (state * 1103515245 + 12345) % 2147483648
        return state % mod
    end
end

local function main()
    local rawItems = genCatalog.generate(N_ITEMS, 7)

    local normalizer = NS.core.TextNormalizer.new({
        protected = { { "km/h", "kmh" }, { "m³", "m3" }, { "r$", " r$ " } },
        currency = { "r$", "$", "€", "£" },
    })
    local builder = NS.core.IndexBuilder.new(normalizer)

    local index
    local buildMs = measureMs(function()
        index = builder:build(rawItems)
    end)

    local diagnostics = NS.app.Diagnostics.new()
    local catalog = {
        items = function()
            return rawItems
        end,
    }
    local lifecycle =
        NS.app.IndexLifecycle.new(diagnostics, { catalog = catalog, builder = builder, clock = FakeClock.new() })
    lifecycle.index = index
    lifecycle.signature = NS.core.Signature.of(rawItems)

    local settings = {
        get = function()
            return 300
        end,
    }
    local svc = NS.app.SearchService.new({ indexLifecycle = lifecycle, normalizer = normalizer, settings = settings })

    local rng = buildRng(99)
    local vocab = {}
    for token in pairs(index.vocabulary) do
        vocab[#vocab + 1] = token
    end
    table.sort(vocab)

    local function randomQuery(nTerms)
        local terms = {}
        for _ = 1, nTerms do
            terms[#terms + 1] = vocab[(rng(#vocab)) + 1]
        end
        return table.concat(terms, " ")
    end

    local simpleLatencies, compositeLatencies = {}, {}
    for _ = 1, N_QUERIES do
        local q = randomQuery(2)
        local ms = measureMs(function()
            svc:search(q)
        end)
        simpleLatencies[#simpleLatencies + 1] = ms
    end
    for _ = 1, N_QUERIES do
        local q = randomQuery(6)
        local ms = measureMs(function()
            svc:search(q)
        end)
        compositeLatencies[#compositeLatencies + 1] = ms
    end

    local metrics = {
        buildMs = buildMs,
        simpleP50Ms = percentile(simpleLatencies, 0.5),
        simpleP95Ms = percentile(simpleLatencies, 0.95),
        compositeP50Ms = percentile(compositeLatencies, 0.5),
        compositeP95Ms = percentile(compositeLatencies, 0.95),
        memoryKb = collectgarbage("count"),
    }

    print(string.format("build:            %.2f ms (%d itens)", metrics.buildMs, N_ITEMS))
    print(string.format("consulta simples:  p50=%.3f ms  p95=%.3f ms", metrics.simpleP50Ms, metrics.simpleP95Ms))
    print(string.format("consulta composta: p50=%.3f ms  p95=%.3f ms", metrics.compositeP50Ms, metrics.compositeP95Ms))
    print(string.format("memória (collectgarbage count): %.1f KB", metrics.memoryKb))

    return metrics
end

local function writeBaseline(metrics, path)
    local fh = assert(io.open(path, "w"))
    fh:write("-- Baseline de performance (tests/bench/run.lua --write-baseline). Não editar à mão.\n")
    fh:write("return {\n")
    for _, key in ipairs({ "buildMs", "simpleP50Ms", "simpleP95Ms", "compositeP50Ms", "compositeP95Ms", "memoryKb" }) do
        fh:write(string.format("    %s = %.4f,\n", key, metrics[key]))
    end
    fh:write("}\n")
    fh:close()
end

local function compare(metrics, path)
    local ok, baseline = pcall(dofile, path)
    if not ok or type(baseline) ~= "table" then
        print("AVISO: baseline ausente/ilegível em " .. path .. " — grave uma com --write-baseline")
        return true
    end
    local failed = false
    for _, key in ipairs({ "buildMs", "simpleP95Ms", "compositeP95Ms" }) do
        local base = baseline[key]
        local cur = metrics[key]
        if base and base > 0 then
            local regression = (cur - base) / base
            if regression > TOLERANCE and (cur - base) > ABS_FLOOR_MS then
                print(
                    string.format(
                        "REGRESSÃO: %s piorou %.1f%% (base=%.3f atual=%.3f, tolerância=%.0f%%)",
                        key,
                        regression * 100,
                        base,
                        cur,
                        TOLERANCE * 100
                    )
                )
                failed = true
            end
        end
    end
    return not failed
end

local metrics = main()

local writeIdx = nil
local compareIdx = nil
for i, arg in ipairs(arg) do
    if arg == "--write-baseline" then
        writeIdx = i
    elseif arg == "--compare" then
        compareIdx = i
    end
end

if writeIdx then
    writeBaseline(metrics, "tests/bench/baseline.lua")
    print("baseline gravada em tests/bench/baseline.lua")
elseif compareIdx then
    local path = arg[compareIdx + 1] or "tests/bench/baseline.lua"
    if not compare(metrics, path) then
        os.exit(1)
    end
    print("bench OK (dentro da tolerância)")
end
