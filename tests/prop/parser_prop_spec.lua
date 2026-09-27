require("tests.support.load").load()
local NS = SmartShopSearch
local FileDataLoader = require("tests.stubs.FileDataLoader")
local Tokenizer = NS.core.Tokenizer

local SEED = 20260927
local N = 2000

local function makeRng(seed)
    local state = seed
    return function(mod)
        state = (state * 1103515245 + 12345) % 2147483648
        return state % mod
    end
end

local VOCAB = {
    "trator",
    "tratores",
    "pulverizador",
    "carreta",
    "john",
    "deere",
    "fendt",
    "acima",
    "de",
    "menos",
    "entre",
    "e",
    "a",
    "cv",
    "hp",
    "kg",
    "mil",
    "reais",
    "r$",
    "200",
    "300",
    "40.000",
    "1,5",
    "150000",
    "xzq",
    "qwrty",
    "banana",
    "6r",
    "250",
    "%()-.[",
    "^$",
    "-5",
    "1e308",
}

local function randomQuery(rng)
    local n = 1 + rng(6)
    local parts = {}
    for _ = 1, n do
        parts[#parts + 1] = VOCAB[rng(#VOCAB) + 1]
    end
    return table.concat(parts, " ")
end

local function buildParser()
    local loader = FileDataLoader.new("src/data")
    local data = NS.app.LinguisticData.new(loader, { "pt", "en" })
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
    }),
        normalizer
end

--- Conta quantos tokens (via Tokenizer) uma constraint/contexto consumiu,
--- re-tokenizando o trecho da string normalizada indicado pelo span.
local function tokenCountInSpan(norm, span)
    local sub = norm:sub(span[1], span[2])
    return #Tokenizer.tokenize(sub)
end

describe("QueryParser (propriedades, 2000 consultas aleatórias, seed fixa)", function()
    local parser, normalizer = buildParser()

    it("nunca lança erro, e todo token é contabilizado em exatamente um destino", function()
        local rng = makeRng(SEED)
        for _ = 1, N do
            local text = randomQuery(rng)
            local query
            assert.has_no.errors(function()
                query = parser:parse(text)
            end)

            local norm = normalizer:normalize(text)
            local totalTokens = #Tokenizer.tokenize(norm)

            local accounted = #query.terms + (query.stopwordsDropped or 0)
            for _, c in ipairs(query.concepts) do
                accounted = accounted + c.consumed
            end
            for _, c in ipairs(query.constraints) do
                accounted = accounted + tokenCountInSpan(norm, c.span)
            end
            if query.context then
                accounted = accounted + tokenCountInSpan(norm, query.context.span)
            end

            assert.are.equal(
                totalTokens,
                accounted,
                string.format(
                    "conservação de tokens falhou para %q (norm=%q): total=%d contabilizado=%d",
                    text,
                    norm,
                    totalTokens,
                    accounted
                )
            )
        end
    end)
end)
