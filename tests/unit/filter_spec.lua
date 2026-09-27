require("tests.support.load").load()
local NS = SmartShopSearch
local FilterEngine = NS.core.FilterEngine
local IndexBuilder = NS.core.IndexBuilder
local TextNormalizer = NS.core.TextNormalizer

local COMMON_UNITS = {
    quantities = {
        { id = "power", canonical = "kw", specs = { "power", "neededPower" }, units = {} },
        { id = "money", canonical = "money", specs = { "price" }, units = {} },
    },
}

local function normalizer()
    return TextNormalizer.new({ protected = {}, currency = {} })
end

local function emptyQuery()
    return { raw = "", terms = {}, concepts = {}, constraints = {}, context = nil, locale = "pt", warnings = {} }
end

describe("FilterEngine", function()
    local index

    before_each(function()
        index = IndexBuilder.new(normalizer()):build({
            {
                xmlFilename = "a.xml",
                name = "Trator A",
                brand = "JOHNDEERE",
                categoryId = "TRACTORSM",
                origin = "base",
                price = 100000,
                specs = { power = { value = 150 } },
            },
            {
                xmlFilename = "b.xml",
                name = "Trator B",
                brand = "FENDT",
                categoryId = "TRACTORSL",
                origin = "base",
                price = 200000,
                specs = { power = { value = 250 } },
            },
            {
                xmlFilename = "c.xml",
                name = "Implemento C (sem power, com neededPower)",
                brand = "KUHN",
                categoryId = "SEEDERSM",
                origin = "mod",
                price = 50000,
                specs = { neededPower = { value = 80 } },
            },
            {
                xmlFilename = "d.xml",
                name = "Implemento D (sem nenhuma spec de potencia)",
                brand = "KUHN",
                categoryId = "PLANTERSM",
                origin = "mod",
                price = 30000,
            },
        })
    end)

    it("filtro de facet (brand) restringe por interseção eliminatória", function()
        local query = emptyQuery()
        local ui = { brand = { ids = { "JOHNDEERE" } } }
        local allowed = FilterEngine.apply(index, query, ui, COMMON_UNITS)
        assert.is_not_nil(allowed)
        assert.is_true(allowed[1])
        assert.is_nil(allowed[2])
    end)

    it("constraint de power exclui itens sem NENHUMA spec da grandeza, sem erro", function()
        local query = emptyQuery()
        query.constraints = { { quantity = "power", op = "gt", min = 100 } }
        local allowed = FilterEngine.apply(index, query, nil, COMMON_UNITS)
        assert.is_not_nil(allowed)
        assert.is_true(allowed[1]) -- power=150 > 100
        assert.is_true(allowed[2]) -- power=250 > 100
        assert.is_nil(allowed[3]) -- só tem neededPower=80, que é < 100
        assert.is_nil(allowed[4]) -- sem nenhuma spec de potência
    end)

    it("item avaliado pela PRIMEIRA spec presente da grandeza (L10: power x neededPower)", function()
        local query = emptyQuery()
        query.constraints = { { quantity = "power", op = "lt", max = 100 } }
        local allowed = FilterEngine.apply(index, query, nil, COMMON_UNITS)
        assert.is_nil(allowed[1]) -- power=150, não < 100
        assert.is_nil(allowed[2]) -- power=250, não < 100
        assert.is_true(allowed[3]) -- sem "power", usa neededPower=80 < 100
        assert.is_nil(allowed[4]) -- sem nenhuma spec
    end)

    it("filtro de UI de preço + constraint textual de money -> interseção", function()
        local query = emptyQuery()
        query.constraints = { { quantity = "money", op = "lt", max = 150000 } }
        local ui = { price = { min = 60000 } }
        local allowed = FilterEngine.apply(index, query, ui, COMMON_UNITS)
        -- a=100000 (< 150000 e >= 60000: ok); b=200000 (excede o max de money); c=50000 (< 60000 do UI); d=30000 (idem)
        assert.is_true(allowed[1])
        assert.is_nil(allowed[2])
        assert.is_nil(allowed[3])
        assert.is_nil(allowed[4])
    end)

    it("sem constraints nem filtros de UI, não restringe (nil)", function()
        local allowed = FilterEngine.apply(index, emptyQuery(), nil, COMMON_UNITS)
        assert.is_nil(allowed)
    end)

    it("resultado vazio (interseção nula) é um conjunto vazio, não nil, e não gera erro", function()
        local query = emptyQuery()
        query.constraints = { { quantity = "power", op = "gt", min = 100000 } } -- ninguém satisfaz
        local allowed
        assert.has_no.errors(function()
            allowed = FilterEngine.apply(index, query, nil, COMMON_UNITS)
        end)
        assert.is_not_nil(allowed)
        assert.is_nil(next(allowed))
    end)
end)
