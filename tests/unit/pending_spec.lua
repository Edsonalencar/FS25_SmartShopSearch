-- Pendências offline da 1.0 (docs/PENDENCIAS.md §2): specs secundárias
-- fatiadas, fuzzy de frase contra itens, motivos de constraint na unidade
-- da consulta, índice compacto e o comando sssSet.
require("tests.support.load").load()
local NS = SmartShopSearch
local FakeClock = require("tests.stubs.FakeClock")
local MemoryLogger = require("tests.stubs.MemoryLogger")
local FileDataLoader = require("tests.stubs.FileDataLoader")

local function normalizer()
    return NS.core.TextNormalizer.new({ protected = {}, currency = { "r$", "$", "€", "£" } })
end

--- Catálogo em memória com camada secundária falsa. `clock` avança 1 ms a
--- cada leitura de XML, para exercitar o orçamento por frame.
local function fakeCatalog(rawItems, secondaryByXml, clock)
    local catalog = { reads = {} }
    function catalog.items()
        return rawItems
    end
    function catalog:secondarySpecsFor(item)
        self.reads[#self.reads + 1] = item.xmlFilename
        if clock then
            clock:advance(0.001)
        end
        local v = secondaryByXml[item.xmlFilename]
        if v == "boom" then
            error("xml ilegível")
        end
        return v or {}
    end
    return catalog
end

local function rawTractor(i, specs)
    return { xmlFilename = "t" .. i .. ".xml", name = "Trator " .. i, species = "vehicle", specs = specs or {} }
end

describe("IndexLifecycle: specs secundárias fatiadas (F6)", function()
    local rawItems, secondary

    before_each(function()
        rawItems = {}
        secondary = {}
        -- 10 itens: power em todos (cobertura 100%), workingWidth em 2 (20%).
        for i = 1, 10 do
            local specs = { power = { value = 100 + i } }
            if i <= 2 then
                specs.workingWidth = { value = 3 }
            end
            rawItems[i] = rawTractor(i, specs)
            secondary["t" .. i .. ".xml"] = { workingWidth = 4 + i, power = 999 }
        end
        secondary["t5.xml"] = "boom"
        secondary["t6.xml"] = { workingWidth = -1 } -- inválido: descartado
    end)

    local function lifecycle(clock, catalog, diagnostics)
        return NS.app.IndexLifecycle.new(diagnostics or NS.app.Diagnostics.new(), {
            catalog = catalog,
            builder = NS.core.IndexBuilder.new(normalizer()),
            clock = clock,
            specIds = { "power", "workingWidth" },
        })
    end

    it("só lê o XML para specs com cobertura < 80%, e só de itens sem a spec", function()
        local catalog = fakeCatalog(rawItems, secondary)
        local lc = lifecycle(nil, catalog)
        assert.is_true(lc:ensure(nil))
        assert.is_true(lc:isBusy()) -- fase secundária pendente
        assert.are.equal(0, #catalog.reads) -- ensure(nil) (busca) nunca lê XML
        assert.is_false(lc:stepPending(nil))
        assert.are.equal(8, #catalog.reads) -- t3..t10
    end)

    it("respeita o orçamento: avança por fatias e aplica tudo só no fim", function()
        local clock = FakeClock.new()
        local catalog = fakeCatalog(rawItems, secondary, clock)
        local lc = lifecycle(clock, catalog)
        lc:ensure(nil)
        local slices = 0
        while lc:stepPending(0.003) do
            slices = slices + 1
            -- durante a fase, nada foi aplicado ao índice ainda
            assert.is_nil(lc.index.items[3].specs.workingWidth)
            assert.is_true(slices < 20)
        end
        assert.is_true(slices >= 2)
        assert.are.equal(7, lc.index.items[3].specs.workingWidth.value)
        assert.are.equal("secondary", lc.index.items[3].specs.workingWidth.source)
    end)

    it("não sobrescreve spec primária, descarta inválidos e isola falhas por item", function()
        local diagnostics = NS.app.Diagnostics.new()
        local lc = lifecycle(nil, fakeCatalog(rawItems, secondary), diagnostics)
        lc:ensure(nil)
        lc:stepPending(nil)
        local items = lc.index.items
        assert.are.equal(101, items[1].specs.power.value) -- primária intacta (secundária dizia 999)
        assert.are.equal(3, items[1].specs.workingWidth.value)
        assert.is_nil(items[5].specs.workingWidth) -- XML falhou
        assert.is_nil(items[6].specs.workingWidth) -- valor inválido
        assert.are.equal(1, diagnostics.skipped["secondary-error"])
        assert.are.equal(6, diagnostics.secondaryAdded) -- t3,t4,t7,t8,t9,t10
        assert.are.equal(0.8, diagnostics.specCoverage.workingWidth)
    end)

    it("as faixas numéricas incluem as specs secundárias, ordenadas", function()
        local lc = lifecycle(nil, fakeCatalog(rawItems, secondary))
        lc:ensure(nil)
        lc:stepPending(nil)
        local ids = lc.index:rangeIds("workingWidth", 7, 9)
        assert.is_true(ids[3] and ids[4] and ids[5] == nil)
        local values = lc.index.numeric.workingWidth.values
        for i = 2, #values do
            assert.is_true(values[i - 1] <= values[i])
        end
    end)

    it("sem specIds ou sem secondarySpecsFor, não há fase secundária", function()
        local catalog = {
            items = function()
                return rawItems
            end,
        }
        local lc =
            NS.app.IndexLifecycle.new(nil, { catalog = catalog, builder = NS.core.IndexBuilder.new(normalizer()) })
        lc:ensure(nil)
        assert.is_false(lc:isBusy())
    end)

    it("stepPending continua um build primário fatiado sem reler o catálogo", function()
        local clock = FakeClock.new()
        local calls = 0
        local catalog = {
            items = function()
                calls = calls + 1
                clock:advance(0.01) -- cada leitura do catálogo "custa" tempo
                return rawItems
            end,
        }
        local lc = NS.app.IndexLifecycle.new(nil, {
            catalog = catalog,
            builder = NS.core.IndexBuilder.new(normalizer()),
            clock = clock,
        })
        assert.is_false(lc:ensure(0)) -- orçamento zero: 1 item por fatia
        while lc:stepPending(0) do
        end
        assert.are.equal(1, calls)
        assert.are.equal(10, lc:itemCount())
    end)
end)

describe("SearchIndex compacto (RNF-003)", function()
    it("postings compartilham o conjunto de campos entre itens", function()
        local index = NS.core.IndexBuilder.new(normalizer()):build({
            { xmlFilename = "a.xml", name = "Alfa", brandTitle = "Deere" },
            { xmlFilename = "b.xml", name = "Beta", brandTitle = "Deere" },
        })
        local postings = index:postingsFor("deere")
        assert.are.equal(postings[1], postings[2])
        assert.are.same({ brand = true }, postings[1])
        -- o IndexedField da marca também é compartilhado
        assert.are.equal(index.items[1].fields.brand, index.items[2].fields.brand)
    end)

    it("token em dois campos do mesmo item vira um conjunto com os dois", function()
        local index = NS.core.IndexBuilder.new(normalizer()):build({
            { xmlFilename = "a.xml", name = "Deere 6R", brandTitle = "Deere" },
        })
        assert.are.same({ name = true, brand = true }, index:postingsFor("deere")[1])
    end)
end)

describe("Fuzzy de frase contra textos de itens (ADR-14)", function()
    local svc

    before_each(function()
        local rawItems = {
            { xmlFilename = "d.xml", name = "6215 TTV", brandTitle = "Deutz-Fahr", categoryTitle = "Tratores" },
            { xmlFilename = "f.xml", name = "Carreta", brandTitle = "Recker", author = "farmerbr" },
            { xmlFilename = "x.xml", name = "Deutz Classic", brandTitle = "Outra" },
        }
        local lc = NS.app.IndexLifecycle.new(nil, {
            catalog = {
                items = function()
                    return rawItems
                end,
            },
            builder = NS.core.IndexBuilder.new(normalizer()),
        })
        svc = NS.app.SearchService.new({ indexLifecycle = lc, normalizer = normalizer() })
    end)

    it("'deuts far' casa a frase 'deutz fahr' e cobre os dois termos", function()
        local results = svc:search("deuts far")
        assert.are.equal("6215 TTV", results[1].item.fields.name.raw)
        assert.are.equal(1, results[1].coverage)
        local phraseReason
        for _, r in ipairs(results[1].reasons) do
            if r.matched == "deutz fahr" then
                phraseReason = r
            end
        end
        assert.is_not_nil(phraseReason)
        assert.are.equal("brand", phraseReason.field)
        assert.truthy(phraseReason.detail:find("frase", 1, true))
    end)

    it("não interfere quando todos os termos casam exatamente", function()
        local results = svc:search("deutz classic")
        assert.are.equal("Deutz Classic", results[1].item.fields.name.raw)
        for _, r in ipairs(results[1].reasons) do
            assert.is_nil(r.detail and r.detail:find("frase", 1, true))
        end
    end)
end)

describe("Motivo de constraint na unidade da consulta (F4)", function()
    local function service(rawItems)
        local loader = FileDataLoader.new("src/data")
        local data = NS.app.LinguisticData.new(loader, { "pt", "en" })
        local commonUnits = data:commonUnits()
        local n =
            NS.core.TextNormalizer.new({ protected = commonUnits.protected, currency = { "r$", "$", "€", "£" } })
        local lc = NS.app.IndexLifecycle.new(nil, {
            catalog = {
                items = function()
                    return rawItems
                end,
            },
            builder = NS.core.IndexBuilder.new(n),
        })
        return NS.app.SearchService.new({ indexLifecycle = lc, normalizer = n, data = data })
    end

    local function constraintDetail(result)
        for _, r in ipairs(result.reasons) do
            if r.kind == "constraint" then
                return r.detail
            end
        end
    end

    it("'entre 200 e 300 cv' mostra '184 kW (250 cv)'", function()
        local svc = service({ { xmlFilename = "a.xml", name = "6R 250", specs = { power = { value = 184 } } } })
        local results = svc:search("entre 200 e 300 cv")
        assert.are.equal("184 kW (250 cv) ∈ [147.1, 220.7]", constraintDetail(results[1]))
    end)

    it("na unidade canônica, sem conversão entre parênteses", function()
        local svc = service({ { xmlFilename = "a.xml", name = "6R 250", specs = { power = { value = 184 } } } })
        local results = svc:search("acima de 150 kw")
        assert.are.equal("184 kW ∈ [150.0, +inf]", constraintDetail(results[1]))
    end)

    it("massa em toneladas e dinheiro sem unidade", function()
        local svc = service({
            {
                xmlFilename = "a.xml",
                categoryId = "TRAILERSM",
                name = "Reboque",
                price = 90000,
                specs = { weight = { value = 24000 } },
            },
        })
        local massResults = svc:search("reboque acima de 20 t")
        assert.are.equal("24000 kg (24 t) ∈ [20000.0, +inf]", constraintDetail(massResults[1]))
        local moneyResults = svc:search("reboque ate 100 mil")
        assert.are.equal("90000 ∈ [-inf, 100000.0]", constraintDetail(moneyResults[1]))
    end)

    it("L10: item com power é avaliado só por power, mesmo com neededPower na faixa", function()
        local svc = service({
            { xmlFilename = "a.xml", name = "Alfa", specs = { power = { value = 50 }, neededPower = { value = 150 } } },
            { xmlFilename = "b.xml", name = "Beta", specs = { neededPower = { value = 150 } } },
        })
        local results = svc:search("acima de 100 kw")
        assert.are.equal(1, #results)
        assert.are.equal("Beta", results[1].item.fields.name.raw)
    end)
end)

describe("Console sssSet (F7)", function()
    local stored

    before_each(function()
        stored = {}
        NS.app.logger = MemoryLogger.new()
        NS.app.settings = {
            get = function(_, key)
                if stored[key] ~= nil then
                    return stored[key]
                end
                return false
            end,
            set = function(_, key, value)
                stored[key] = value
            end,
        }
    end)

    it("altera showReasons e incremental", function()
        assert.are.equal("showReasons = true", NS.app.Console.set("showReasons", "1"))
        assert.is_true(stored["ui#showReasons"])
        assert.are.equal("incremental = false", NS.app.Console.set("incremental", "off"))
        assert.is_false(stored["ui#incremental"])
    end)

    it("sem argumentos lista os valores atuais", function()
        stored["ui#showReasons"] = true
        local out = NS.app.Console.set()
        assert.truthy(out:find("showReasons = true", 1, true))
        assert.truthy(out:find("incremental = false", 1, true))
    end)

    it("rejeita chave desconhecida e valor inválido sem gravar", function()
        assert.truthy(NS.app.Console.set("debug", "1"):find("chave desconhecida", 1, true))
        assert.truthy(NS.app.Console.set("showReasons", "talvez"):find("uso:", 1, true))
        assert.is_nil(next(stored))
    end)
end)
