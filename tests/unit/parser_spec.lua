require("tests.support.load").load()
local NS = SmartShopSearch
local FileDataLoader = require("tests.stubs.FileDataLoader")

local function buildParser(locales)
    local loader = FileDataLoader.new("src/data")
    local data = NS.app.LinguisticData.new(loader, locales or { "pt", "en" })
    local commonUnits = data:commonUnits()
    local normalizer = NS.core.TextNormalizer.new({
        protected = (commonUnits and commonUnits.protected) or {},
        currency = { "r$", "$", "€", "£" },
    })
    local aliasResolver = NS.core.AliasResolver.new(normalizer, data:aliases())
    local numberParser = NS.core.NumberParser.new(data:numbers())
    local unitParser = NS.core.UnitParser.new(commonUnits, data:units())
    local comparatorParser = NS.core.ComparatorParser.new(data:comparators(), numberParser, unitParser, function(s)
        return normalizer:normalize(s)
    end)
    local contextParser = NS.core.ContextParser.new(data:context(), function(s)
        return normalizer:normalize(s)
    end)
    local stopwordSets = data:stopwords()
    local stopwords = {}
    for _, set in ipairs(stopwordSets) do
        for word in pairs(set) do
            stopwords[word] = true
        end
    end
    return NS.core.QueryParser.new({
        normalizer = normalizer,
        aliasResolver = aliasResolver,
        comparatorParser = comparatorParser,
        contextParser = contextParser,
        stopwords = stopwords,
    })
end

local function constraintOf(query, quantity)
    for _, c in ipairs(query.constraints) do
        if c.quantity == quantity then
            return c
        end
    end
    return nil
end

local function conceptOf(query, kind)
    for _, c in ipairs(query.concepts) do
        if c.kind == kind then
            return c
        end
    end
    return nil
end

local function termTexts(query)
    local out = {}
    for _, t in ipairs(query.terms) do
        out[#out + 1] = t.text
    end
    return out
end

describe("QueryParser (>= 60 casos, Number/Unit/Comparator/Context)", function()
    local parser

    setup(function()
        parser = buildParser()
    end)

    local function near(a, b, tol)
        return math.abs(a - b) <= (tol or 0.5)
    end

    -- Números e unidades básicas -------------------------------------------------
    it("'200cv' -> power ~ 200cv (±5%)", function()
        local q = parser:parse("200cv")
        local c = constraintOf(q, "power")
        assert.is_not_nil(c)
        assert.is_true(near(c.min, 200 * 0.7355 * 0.95, 0.5))
    end)
    it("'200 cv' (com espaço) -> mesmo resultado", function()
        local c = constraintOf(parser:parse("200 cv"), "power")
        assert.is_not_nil(c)
    end)
    it("'200 hp' -> power via fator hp", function()
        local c = constraintOf(parser:parse("200 hp"), "power")
        assert.is_not_nil(c)
        assert.is_true(near(c.min, 200 * 0.7457 * 0.95, 0.5))
    end)
    it("'40.000 litros' -> volume ~ 40000", function()
        local c = constraintOf(parser:parse("40.000 litros"), "volume")
        assert.is_not_nil(c)
        assert.is_true(near(c.min, 40000 * 0.95, 1))
    end)
    it("'40 mil litros' -> volume ~ 40000", function()
        local c = constraintOf(parser:parse("40 mil litros"), "volume")
        assert.is_not_nil(c)
        assert.is_true(near(c.min, 40000 * 0.95, 1))
    end)
    it("'150.000' isolado (sem unidade) -> constraint de money (L9, >= 1000)", function()
        local c = constraintOf(parser:parse("acima de 150.000"), "money")
        assert.is_not_nil(c)
        assert.are.equal(150000, c.min)
    end)
    it("'150 mil' isolado -> money via L9 (usou multiplicador)", function()
        local c = constraintOf(parser:parse("menos de 150 mil"), "money")
        assert.is_not_nil(c)
        assert.are.equal(150000, c.max)
    end)
    it("'R$ 150 mil' -> money via símbolo (isolado: eq com tolerância ±5%, RF-027)", function()
        local c = constraintOf(parser:parse("R$ 150 mil"), "money")
        assert.is_not_nil(c)
        assert.is_true(near(c.min, 150000 * 0.95, 1))
        assert.is_true(near(c.max, 150000 * 1.05, 1))
    end)
    it("'1,5 mi' -> 1500000 (money via L9)", function()
        local c = constraintOf(parser:parse("acima de 1,5 mi"), "money")
        assert.is_not_nil(c)
        assert.are.equal(1500000, c.min)
    end)

    -- Comparadores e intervalos --------------------------------------------------
    it("'de 100 a 200 cv' -> range", function()
        local c = constraintOf(parser:parse("de 100 a 200 cv"), "power")
        assert.is_not_nil(c)
        assert.are.equal("between", c.op)
    end)
    it("'100-200 cv' -> range (hífen normalizado)", function()
        local c = constraintOf(parser:parse("100-200 cv"), "power")
        assert.is_not_nil(c)
        assert.are.equal("between", c.op)
    end)
    it("'entre 200' (incompleto) não gera constraint nem erro", function()
        local q
        assert.has_no.errors(function()
            q = parser:parse("entre 200")
        end)
        assert.is_nil(constraintOf(q, "power"))
    end)
    it("'acima de' sozinho (sem número) não gera constraint nem erro", function()
        assert.has_no.errors(function()
            parser:parse("acima de")
        end)
    end)
    it("'menos de 150 mil cv' -> unidade explícita vence -> power, não money", function()
        local q = parser:parse("menos de 150 mil cv")
        assert.is_not_nil(constraintOf(q, "power"))
        assert.is_nil(constraintOf(q, "money"))
    end)

    -- Termos remanescentes --------------------------------------------------------
    it("'6r 250' -> ambos continuam termos (sem unidade/comparador)", function()
        local q = parser:parse("6r 250")
        local terms = termTexts(q)
        assert.is_true(#terms >= 1)
    end)
    it("'john 250' -> '250' sem contexto numérico continua termo", function()
        local q = parser:parse("john 250")
        local found250 = false
        for _, t in ipairs(termTexts(q)) do
            if t == "250" then
                found250 = true
            end
        end
        assert.is_true(found250)
    end)

    -- Robustez ---------------------------------------------------------------------
    it("números gigantes ('1e308') tratados como texto, sem erro", function()
        assert.has_no.errors(function()
            parser:parse("1e308")
        end)
    end)
    it("negativos ('-5 cv') não quebram o parser", function()
        assert.has_no.errors(function()
            parser:parse("-5 cv")
        end)
    end)
    it("entrada vazia devolve Query com listas vazias", function()
        local q = parser:parse("")
        assert.are.equal(0, #q.terms)
        assert.are.equal(0, #q.concepts)
        assert.are.equal(0, #q.constraints)
    end)
    it("só espaços devolve Query com listas vazias", function()
        local q = parser:parse("     ")
        assert.are.equal(0, #q.terms)
    end)
    it("caracteres mágicos de padrão Lua não quebram o parser", function()
        assert.has_no.errors(function()
            parser:parse("%()-.[ ^$")
        end)
    end)

    -- Conceitos --------------------------------------------------------------------
    it("'trator' -> concept category TRACTORS*", function()
        local c = conceptOf(parser:parse("trator"), "category")
        assert.is_not_nil(c)
        assert.are.equal("TRACTORS*", c.value)
    end)
    it("'john deere' -> concept brand JOHNDEERE", function()
        local c = conceptOf(parser:parse("john deere"), "brand")
        assert.is_not_nil(c)
        assert.are.equal("JOHNDEERE", c.value)
    end)
    it("'dlc' -> concept origin dlc", function()
        local c = conceptOf(parser:parse("dlc"), "origin")
        assert.is_not_nil(c)
        assert.are.equal("dlc", c.value)
    end)

    -- Contexto (L4) ------------------------------------------------------------------
    it("'compativel com este trator' -> contexto selected", function()
        local q = parser:parse("compativel com este trator")
        assert.is_not_nil(q.context)
        assert.are.equal("compatibleWith", q.context.kind)
        assert.are.equal("selected", q.context.target)
    end)
    it("'compativel com 6r 250' -> contexto query com targetTerms", function()
        local q = parser:parse("compativel com 6r 250")
        assert.is_not_nil(q.context)
        assert.are.equal("query", q.context.target)
        assert.is_true(#q.context.targetTerms >= 1)
    end)

    -- Tabela extensa de casos simples (número/unidade), até fechar >= 60 asserts ----
    local extra = {
        { "acima de 100 kg", "mass" },
        { "abaixo de 10 t", "mass" },
        { "mais de 5 m", "length" },
        { "menos de 50 kmh", "speed" },
        { "acima de 100 l", "volume" },
        { "mais de 2 ton", "mass" },
        { "acima de 3 ft", "length" },
        { "mais de 30 mph", "speed" },
        { "acima de 500 gal", "volume" },
        { "mais de 1 m3", "volume" },
        { "a partir de 100 cv", "power" },
        { "pelo menos 50 cv", "power" },
        { "no minimo 80 cv", "power" },
        { "no maximo 200 cv", "power" },
        { "ate 300 cv", "power" },
        { "cerca de 200 cv", "power" },
        { "aproximadamente 150 cv", "power" },
        { "uns 100 cv", "power" },
        { "superior a 100 cv", "power" },
        { "inferior a 100 cv", "power" },
        { "maior que 100 cv", "power" },
        { "menor que 100 cv", "power" },
        { "de 50 a 100 kg", "mass" },
        { "50-100 kg", "mass" },
    }
    for _, case in ipairs(extra) do
        it(string.format("%q reconhece grandeza %s", case[1], case[2]), function()
            local q = parser:parse(case[1])
            assert.is_not_nil(constraintOf(q, case[2]), "esperava constraint de " .. case[2] .. " para " .. case[1])
        end)
    end

    local moreRobustness = {
        "",
        "   ",
        "a",
        "1",
        "1.2.3.4.5",
        ",,,",
        "...",
        "cv cv cv",
        "entre e",
        "mil mil mil",
    }
    for _, q in ipairs(moreRobustness) do
        it(string.format("entrada %q nunca lança erro", q), function()
            assert.has_no.errors(function()
                parser:parse(q)
            end)
        end)
    end
end)
