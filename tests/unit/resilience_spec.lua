require("tests.support.load").load()
local NS = SmartShopSearch
local TextNormalizer = NS.core.TextNormalizer
local IndexBuilder = NS.core.IndexBuilder
local MemoryLogger = require("tests.stubs.MemoryLogger")
local FixtureCatalogSource = require("tests.stubs.FixtureCatalogSource")

describe("SearchService resiliência (AC-RES-03)", function()
    it("catálogo cujo items() lança erro devolve {} sem propagar, com uma linha de erro", function()
        NS.app.logger = MemoryLogger.new()
        NS.app.state = NS.app.StateMachine.new(NS.app.logger)
        NS.app.SafeCall.failures = {}

        local normalizer = TextNormalizer.new({ protected = {}, currency = {} })
        local catalog = FixtureCatalogSource.new("tests/fixtures/catalog/synthetic.xml", { failOnItems = true })
        local builder = IndexBuilder.new(normalizer)
        local diagnostics = NS.app.Diagnostics.new()
        local lifecycle = NS.app.IndexLifecycle.new(diagnostics, { catalog = catalog, builder = builder })
        local settings = { get = function() end }
        local svc =
            NS.app.SearchService.new({ indexLifecycle = lifecycle, normalizer = normalizer, settings = settings })

        local results, query
        assert.has_no.errors(function()
            results, query = svc:search("trator")
        end)
        assert.are.same({}, results)
        assert.is_nil(query)
        assert.is_true(NS.app.logger:hasLevel("error"))
        assert.are.equal(1, NS.app.logger:countLevel("error"))
    end)

    it("texto de consulta não-string não gera erro", function()
        local normalizer = TextNormalizer.new({ protected = {}, currency = {} })
        local svc = NS.app.SearchService.new({ normalizer = normalizer, settings = { get = function() end } })
        assert.has_no.errors(function()
            svc:search(nil)
        end)
    end)

    it("consulta vazia ou só espaços devolve {} sem erro (RF-005)", function()
        local normalizer = TextNormalizer.new({ protected = {}, currency = {} })
        local svc = NS.app.SearchService.new({ normalizer = normalizer, settings = { get = function() end } })
        local results = svc:search("   ")
        assert.are.same({}, results)
    end)
end)
