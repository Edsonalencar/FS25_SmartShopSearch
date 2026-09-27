#!/usr/bin/env lua
-- Benchmark do motor de busca (PRD §15): build do índice sobre um catálogo
-- sintético de 3000 itens, memória do índice e p50/p95 de consultas simples
-- e compostas.
--
-- Estabilidade: cada métrica de tempo é a mediana de REPEATS execuções. O
-- critério de falha são as metas absolutas do PRD §15; a comparação com a
-- baseline só avisa (numa máquina compartilhada, a variação relativa reflete
-- mais a carga do SO do que o código). Com --strict, uma regressão relativa
-- acima da tolerância também falha.
--
-- Uso:
--   lua tests/bench/run.lua --write-baseline           -- grava tests/bench/baseline.lua
--   lua tests/bench/run.lua --compare <arquivo>        -- metas absolutas + aviso de regressão
--   lua tests/bench/run.lua --compare <arquivo> --strict
package.path = "./?.lua;" .. package.path

require("tests.support.load").load()
local NS = SmartShopSearch
local genCatalog = require("tests.bench.gen_catalog")
local FakeClock = require("tests.stubs.FakeClock")
local FileDataLoader = require("tests.stubs.FileDataLoader")

local N_ITEMS = 3000
local N_QUERIES = 200
local REPEATS = 5
local TOLERANCE = 0.20
-- Piso absoluto (ms) abaixo do qual uma regressão relativa é ignorada: em
-- métricas de poucos milissegundos, ruído de GC/agendamento do SO produz
-- variações relativas grandes sem significado prático.
local ABS_FLOOR_MS = { buildMs = 20.0, simpleP95Ms = 2.0, compositeP95Ms = 2.0 }

-- Metas do PRD §15. O build tem meta de 150 ms para 2000 itens; o bench usa
-- 3000 (a mesma base da meta de memória), então a meta escala linearmente.
local TARGETS = {
    buildMs = 150 * N_ITEMS / 2000,
    simpleP95Ms = 5,
    compositeP95Ms = 15,
    indexMemoryKb = 8 * 1024,
}

-- Sufixos com 2 constraints para as consultas compostas (5+ termos no total).
local CONSTRAINT_SUFFIXES = {
    "acima de 100 cv ate 200 mil",
    "entre 150 e 300 cv por menos de 250 mil",
    "mais de 5 m abaixo de 90000",
}

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

local function median(list)
    return percentile(list, 0.5)
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

local function fullGc()
    collectgarbage("collect")
    collectgarbage("collect")
end

local function makeNormalizer(data)
    local commonUnits = data:commonUnits()
    return NS.core.TextNormalizer.new({
        protected = (commonUnits and commonUnits.protected) or {},
        currency = { "r$", "$", "€", "£" },
    })
end

--- Memória retida só pelo índice: delta de `collectgarbage("count")` entre
--- antes e depois do build, com GC completo nos dois pontos e o catálogo
--- (RawItem[]) já alocado antes da primeira medição.
local function measureIndexMemoryKb(builder, rawItems)
    fullGc()
    local before = collectgarbage("count")
    local index = builder:build(rawItems)
    fullGc()
    local after = collectgarbage("count")
    assert(#index.items > 0)
    return after - before
end

local function runOnce(rawItems, data, normalizer)
    local builder = NS.core.IndexBuilder.new(normalizer)

    fullGc()
    local index
    local buildMs = measureMs(function()
        index = builder:build(rawItems)
    end)

    local catalog = {
        items = function()
            return rawItems
        end,
    }
    local lifecycle = NS.app.IndexLifecycle.new(
        NS.app.Diagnostics.new(),
        { catalog = catalog, builder = builder, clock = FakeClock.new() }
    )
    lifecycle.index = index
    lifecycle.signature = NS.core.Signature.of(rawItems)

    local settings = {
        get = function()
            return 300
        end,
    }
    local svc = NS.app.SearchService.new({
        indexLifecycle = lifecycle,
        normalizer = normalizer,
        settings = settings,
        data = data,
    })

    local rng = buildRng(99)
    local vocab = {}
    for token in pairs(index.vocabulary) do
        vocab[#vocab + 1] = token
    end
    table.sort(vocab)

    local function randomTerms(nTerms)
        local terms = {}
        for _ = 1, nTerms do
            terms[#terms + 1] = vocab[(rng(#vocab)) + 1]
        end
        return table.concat(terms, " ")
    end

    local simpleLatencies, compositeLatencies = {}, {}
    for _ = 1, N_QUERIES do
        local q = randomTerms(2)
        simpleLatencies[#simpleLatencies + 1] = measureMs(function()
            svc:search(q)
        end)
    end
    for i = 1, N_QUERIES do
        local q = randomTerms(3) .. " " .. CONSTRAINT_SUFFIXES[(i % #CONSTRAINT_SUFFIXES) + 1]
        compositeLatencies[#compositeLatencies + 1] = measureMs(function()
            svc:search(q)
        end)
    end

    return {
        buildMs = buildMs,
        simpleP50Ms = percentile(simpleLatencies, 0.5),
        simpleP95Ms = percentile(simpleLatencies, 0.95),
        compositeP50Ms = percentile(compositeLatencies, 0.5),
        compositeP95Ms = percentile(compositeLatencies, 0.95),
    }
end

local TIME_KEYS = { "buildMs", "simpleP50Ms", "simpleP95Ms", "compositeP50Ms", "compositeP95Ms" }

local function main()
    local rawItems = genCatalog.generate(N_ITEMS, 7)
    local data = NS.app.LinguisticData.new(FileDataLoader.new("src/data"), { "pt", "en" })
    local normalizer = makeNormalizer(data)

    local runs = {}
    for r = 1, REPEATS do
        runs[r] = runOnce(rawItems, data, normalizer)
    end
    local metrics = {}
    for _, key in ipairs(TIME_KEYS) do
        local values = {}
        for r = 1, REPEATS do
            values[r] = runs[r][key]
        end
        metrics[key] = median(values)
    end
    metrics.indexMemoryKb = measureIndexMemoryKb(NS.core.IndexBuilder.new(normalizer), rawItems)

    print(string.format("mediana de %d execuções", REPEATS))
    print(string.format("build:            %.2f ms (%d itens)", metrics.buildMs, N_ITEMS))
    print(string.format("consulta simples:  p50=%.3f ms  p95=%.3f ms", metrics.simpleP50Ms, metrics.simpleP95Ms))
    print(string.format("consulta composta: p50=%.3f ms  p95=%.3f ms", metrics.compositeP50Ms, metrics.compositeP95Ms))
    print(string.format("memória do índice: %.1f KB (delta isolado, após GC completo)", metrics.indexMemoryKb))

    return metrics
end

local function writeBaseline(metrics, path)
    local fh = assert(io.open(path, "w"))
    fh:write("-- Baseline de performance (tests/bench/run.lua --write-baseline). Não editar à mão.\n")
    fh:write("return {\n")
    for _, key in ipairs({
        "buildMs",
        "simpleP50Ms",
        "simpleP95Ms",
        "compositeP50Ms",
        "compositeP95Ms",
        "indexMemoryKb",
    }) do
        fh:write(string.format("    %s = %.4f,\n", key, metrics[key]))
    end
    fh:write("}\n")
    fh:close()
end

--- Metas absolutas do PRD §15: único critério de falha sem --strict.
local function checkTargets(metrics)
    local ok = true
    for _, key in ipairs({ "buildMs", "simpleP95Ms", "compositeP95Ms", "indexMemoryKb" }) do
        if metrics[key] > TARGETS[key] then
            print(string.format("META ESTOURADA: %s=%.3f > %.3f (PRD §15)", key, metrics[key], TARGETS[key]))
            ok = false
        end
    end
    return ok
end

--- @return boolean ok  false só se houver regressão e `strict` for true
local function compare(metrics, path, strict)
    local ok, baseline = pcall(dofile, path)
    if not ok or type(baseline) ~= "table" then
        print("AVISO: baseline ausente/ilegível em " .. path .. " — grave uma com --write-baseline")
        return true
    end
    local regressed = false
    for _, key in ipairs({ "buildMs", "simpleP95Ms", "compositeP95Ms" }) do
        local base = baseline[key]
        local cur = metrics[key]
        if base and base > 0 then
            local regression = (cur - base) / base
            if regression > TOLERANCE and (cur - base) > (ABS_FLOOR_MS[key] or 2.0) then
                print(
                    string.format(
                        "%s: %s piorou %.1f%% (base=%.3f atual=%.3f, tolerância=%.0f%%)",
                        strict and "REGRESSÃO" or "AVISO",
                        key,
                        regression * 100,
                        base,
                        cur,
                        TOLERANCE * 100
                    )
                )
                regressed = true
            end
        end
    end
    return not (strict and regressed)
end

local metrics = main()

local writeIdx, compareIdx, strict = nil, nil, false
for i, a in ipairs(arg) do
    if a == "--write-baseline" then
        writeIdx = i
    elseif a == "--compare" then
        compareIdx = i
    elseif a == "--strict" then
        strict = true
    end
end

if writeIdx then
    writeBaseline(metrics, "tests/bench/baseline.lua")
    print("baseline gravada em tests/bench/baseline.lua")
elseif compareIdx then
    local path = arg[compareIdx + 1]
    if not path or path:sub(1, 2) == "--" then
        path = "tests/bench/baseline.lua"
    end
    local targetsOk = checkTargets(metrics)
    local compareOk = compare(metrics, path, strict)
    if not (targetsOk and compareOk) then
        os.exit(1)
    end
    print("bench OK (metas do PRD §15 atendidas)")
end
