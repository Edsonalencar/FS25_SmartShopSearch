require("tests.support.load").load()
local NS = SmartShopSearch
local SearchScorer = NS.core.SearchScorer
local Ranker = NS.core.Ranker
local Weights = NS.core.Weights
local Models = NS.core.Models

local function term(text, idf)
    return { text = text, span = { 1, #text }, fuzzyMax = 0, idf = idf or 1 }
end

local function itemWithName(name)
    return { fields = { name = { raw = name, norm = name:lower(), tokens = {} } } }
end

describe("SearchScorer", function()
    it("exato pontua mais que prefixo no mesmo campo", function()
        local query = { terms = { term("trator") }, concepts = {} }
        local exactHit = {
            [1] = {
                value = Weights.fields.name * Weights.types.exact,
                field = "name",
                reason = Models.reason("exact", "name", "trator", "trator"),
            },
        }
        local prefixHit = {
            [1] = {
                value = Weights.fields.name * Weights.types.prefix * 0.6,
                field = "name",
                reason = Models.reason("prefix", "name", "trator", "tratores"),
            },
        }
        local item = itemWithName("x")
        local sExact = SearchScorer.score(query, item, exactHit, {}, Weights)
        local sPrefix = SearchScorer.score(query, item, prefixHit, {}, Weights)
        assert.is_true(sExact > sPrefix)
    end)

    it("mais termos satisfeitos aumenta a relevância (AC-RNK-02)", function()
        local query = { terms = { term("a"), term("b") }, concepts = {} }
        local oneHit = { [1] = { value = 1, field = "name", reason = Models.reason("exact", "name", "a", "a") } }
        local twoHits = {
            [1] = { value = 1, field = "name", reason = Models.reason("exact", "name", "a", "a") },
            [2] = { value = 1, field = "name", reason = Models.reason("exact", "name", "b", "b") },
        }
        local item = itemWithName("x")
        local sOne = SearchScorer.score(query, item, oneHit, {}, Weights)
        local sTwo = SearchScorer.score(query, item, twoHits, {}, Weights)
        assert.is_true(sTwo > sOne)
    end)

    it("hits só em campos secundários (mod/author/dlc) recebem penalidade", function()
        local query = { terms = { term("x") }, concepts = {} }
        local secondaryHit = {
            [1] = {
                value = Weights.fields.author,
                field = "author",
                reason = Models.reason("exact", "author", "x", "x"),
            },
        }
        local primaryHit = {
            [1] = { value = Weights.fields.author, field = "name", reason = Models.reason("exact", "name", "x", "x") },
        }
        local item = itemWithName("x")
        local sSecondary = SearchScorer.score(query, item, secondaryHit, {}, Weights)
        local sPrimary = SearchScorer.score(query, item, primaryHit, {}, Weights)
        assert.is_true(sPrimary > sSecondary)
    end)

    it("reasons é sempre preenchido quando há hits (RF-051)", function()
        local query = { terms = { term("a") }, concepts = {} }
        local hits = { [1] = { value = 1, field = "name", reason = Models.reason("exact", "name", "a", "a") } }
        local _, _, reasons = SearchScorer.score(query, itemWithName("x"), hits, {}, Weights)
        assert.are.equal(1, #reasons)
    end)

    it("consulta só com constraints/filtros (sem termos/conceitos) pontua 1", function()
        local query = { terms = {}, concepts = {} }
        local s, cov = SearchScorer.score(query, itemWithName("x"), {}, {}, Weights)
        assert.are.equal(1, s)
        assert.are.equal(1, cov)
    end)
end)

describe("Ranker", function()
    it("ordena por score desc, depois coverage desc, depois nome asc", function()
        local results = {
            Models.result(itemWithName("Zebra"), 0.9, 1.0, {}),
            Models.result(itemWithName("Alfa"), 0.9, 1.0, {}),
            Models.result(itemWithName("Beta"), 0.95, 1.0, {}),
        }
        local ranked = Ranker.rank(results, Weights, 10)
        assert.are.equal("Beta", ranked[1].item.fields.name.raw)
        assert.are.equal("Alfa", ranked[2].item.fields.name.raw)
        assert.are.equal("Zebra", ranked[3].item.fields.name.raw)
    end)

    it("corta resultados abaixo do score mínimo relativo/absoluto", function()
        local results = {
            Models.result(itemWithName("Bom"), 1.0, 1.0, {}),
            Models.result(itemWithName("Fraco"), 0.01, 1.0, {}),
        }
        local ranked = Ranker.rank(results, Weights, 10)
        assert.are.equal(1, #ranked)
        assert.are.equal("Bom", ranked[1].item.fields.name.raw)
    end)

    it("respeita maxResults", function()
        local results = {}
        for i = 1, 5 do
            results[i] = Models.result(itemWithName("Item" .. i), 1.0, 1.0, {})
        end
        local ranked = Ranker.rank(results, Weights, 2)
        assert.are.equal(2, #ranked)
    end)

    it("lista vazia devolve lista vazia", function()
        assert.are.equal(0, #Ranker.rank({}, Weights, 10))
    end)
end)
