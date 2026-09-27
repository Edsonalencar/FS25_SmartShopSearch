require("tests.support.load").load()
local NS = SmartShopSearch
local Osa = NS.core.Osa
local FuzzyMatcher = NS.core.FuzzyMatcher
local TrigramIndex = NS.core.TrigramIndex

describe("Osa.distance", function()
    local cases = {
        { "trtor", "trator", 1 }, -- remoção
        { "tratro", "trator", 1 }, -- transposição
        { "jhon", "john", 1 }, -- transposição
        { "pulverizdor", "pulverizador", 1 }, -- remoção
        { "abc", "xyz", 3 }, -- substituição total
    }
    for _, c in ipairs(cases) do
        it(string.format("d(%q,%q) com max=5 é %d", c[1], c[2], c[3]), function()
            assert.are.equal(c[3], Osa.distance(c[1], c[2], 5))
        end)
    end

    it("early exit retorna max+1 quando a distância excede o limite", function()
        assert.are.equal(3, Osa.distance("abc", "xyz", 2))
    end)

    it("distância zero para strings iguais", function()
        assert.are.equal(0, Osa.distance("trator", "trator", 5))
    end)
end)

describe("FuzzyMatcher.maxDistFor (limiar por tamanho, RF-021/022)", function()
    it("<=3 bytes: só exato/prefixo (dist 0)", function()
        assert.are.equal(0, FuzzyMatcher.maxDistFor(1))
        assert.are.equal(0, FuzzyMatcher.maxDistFor(3))
    end)
    it("4-5 bytes: dist 1", function()
        assert.are.equal(1, FuzzyMatcher.maxDistFor(4))
        assert.are.equal(1, FuzzyMatcher.maxDistFor(5))
    end)
    it("6-9 bytes: dist 2", function()
        assert.are.equal(2, FuzzyMatcher.maxDistFor(6))
        assert.are.equal(2, FuzzyMatcher.maxDistFor(9))
    end)
    it(">=10 bytes: dist 3", function()
        assert.are.equal(3, FuzzyMatcher.maxDistFor(10))
        assert.are.equal(3, FuzzyMatcher.maxDistFor(20))
    end)
end)

describe("FuzzyMatcher.matchPhraseWindow (fuzzy de frase, L6/ADR-14)", function()
    local function tok(s)
        local out = {}
        local pos = 1
        for word in s:gmatch("%S+") do
            out[#out + 1] = { text = word, s = pos, e = pos + #word - 1 }
            pos = pos + #word + 1
        end
        return out
    end

    it("'jon dere' casa com 'john deere' (distância 2, frase aceita)", function()
        local trigramIndex = TrigramIndex.build({ "john deere" })
        local result = FuzzyMatcher.matchPhraseWindow(trigramIndex, tok("jon dere"), 1, 2)
        assert.is_not_nil(result)
        assert.are.equal("john deere", result.matched)
        assert.are.equal(2, result.consumed)
    end)

    it("'jo de' não casa com 'john deere' (distância grande demais, rejeitada)", function()
        local trigramIndex = TrigramIndex.build({ "john deere" })
        local result = FuzzyMatcher.matchPhraseWindow(trigramIndex, tok("jo de"), 1, 2)
        assert.is_nil(result)
    end)
end)

describe("FuzzyMatcher.matchToken", function()
    it("token com <=3 bytes não gera candidatos fuzzy (RF-022)", function()
        local index = NS.core.IndexBuilder
            .new(NS.core.TextNormalizer.new({ protected = {}, currency = {} }))
            :build({ { xmlFilename = "a.xml", name = "trator" } })
        local candidates = FuzzyMatcher.matchToken(index, "tr")
        assert.are.same({}, candidates)
    end)
end)
