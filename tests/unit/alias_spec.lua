require("tests.support.load").load()
local NS = SmartShopSearch
local AliasResolver = NS.core.AliasResolver
local Tokenizer = NS.core.Tokenizer
local FileDataLoader = require("tests.stubs.FileDataLoader")

local function normalizer()
    return NS.core.TextNormalizer.new({ protected = {}, currency = {} })
end

local function resolverFor(locales)
    local NORM = normalizer()
    local loader = FileDataLoader.new("src/data")
    local ling = NS.app.LinguisticData.new(loader, locales)
    return AliasResolver.new(NORM, ling:aliases()), NORM
end

local function firstResolution(resolver, norm, text, fuzzy)
    local tokens = Tokenizer.tokenize(norm:normalize(text))
    return resolver:resolveAt(tokens, 1, fuzzy)
end

describe("AliasResolver (pt + en)", function()
    local resolver, norm

    before_each(function()
        resolver, norm = resolverFor({ "pt", "en" })
    end)

    it("resolve single-palavra exata (categoria)", function()
        local r = firstResolution(resolver, norm, "trator", false)
        assert.are.equal("category", r.kind)
        assert.are.equal("TRACTORS*", r.id)
        assert.are.equal(1.0, r.confidence)
        assert.are.equal(1, r.consumed)
    end)

    it("resolve frase multi-palavra exata (marca), consumindo os dois tokens", function()
        local tokens = Tokenizer.tokenize(norm:normalize("john deere 6r"))
        local r = resolver:resolveAt(tokens, 1, false)
        assert.are.equal("brand", r.kind)
        assert.are.equal("JOHNDEERE", r.id)
        assert.are.equal(2, r.consumed)
    end)

    it("não resolve token desconhecido", function()
        assert.is_nil(firstResolution(resolver, norm, "xyzabc", true))
    end)

    it("resolve por fuzzy quando habilitado, e não resolve quando desabilitado", function()
        local withFuzzy = firstResolution(resolver, norm, "trtor", true)
        assert.is_not_nil(withFuzzy)
        assert.are.equal("TRACTORS*", withFuzzy.id)

        local withoutFuzzy = firstResolution(resolver, norm, "trtor", false)
        assert.is_nil(withoutFuzzy)
    end)
end)

describe("AliasResolver (troca de idioma sem mudar código, RF-025/059)", function()
    it("resolve 'schlepper' -> TRACTORS* com data/de, sem tocar no código", function()
        local resolver, norm = resolverFor({ "de", "en" })
        local r = firstResolution(resolver, norm, "schlepper", false)
        assert.is_not_nil(r)
        assert.are.equal("category", r.kind)
        assert.are.equal("TRACTORS*", r.id)
    end)
end)
