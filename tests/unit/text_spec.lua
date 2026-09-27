require("tests.support.load").load()
local NS = SmartShopSearch
local Utf8 = NS.core.Utf8
local TextNormalizer = NS.core.TextNormalizer
local Tokenizer = NS.core.Tokenizer

local function normalizer()
    return TextNormalizer.new({
        protected = { { "km/h", "kmh" }, { "m³", "m3" }, { "r$", " r$ " } },
        currency = { "r$", "$", "€", "£" },
    })
end

local function collapse(s)
    return (s:gsub("%s+", " "):match("^%s*(.-)%s*$"))
end

describe("Utf8", function()
    it("dobra acentos Latin-1/Latin Extended-A para ASCII", function()
        assert.are.equal("AEIOUaeioucaoaeoC", Utf8.fold("ÁÉÍÓÚáéíóúçãõâêôÇ"))
        assert.are.equal("AEIOU", Utf8.fold("ÁÉÍÓÚ"))
        assert.are.equal("c", Utf8.fold("ç"))
    end)

    it("preserva bytes inválidos/fora do alcance de FOLD", function()
        local s = "abc\xff\xfedef"
        assert.are.equal(s, Utf8.fold(s))
    end)

    it("len conta caracteres, não bytes", function()
        assert.are.equal(4, Utf8.len("café"))
        assert.are.equal(12, Utf8.len("normal ascii"))
    end)
end)

describe("TextNormalizer", function()
    local TN

    before_each(function()
        TN = normalizer()
    end)

    it("separa fronteira letra-dígito", function()
        assert.are.equal("200 cv", collapse(TN:normalize("200cv")))
    end)

    it("preserva separador de milhar entre dígitos", function()
        assert.are.equal("40.000 l", collapse(TN:normalize("40.000 L")))
    end)

    it("isola o símbolo de moeda protegido (r$)", function()
        assert.are.equal("r$ 150 mil", collapse(TN:normalize("R$150 mil")))
    end)

    it("aplica sequências protegidas de unidade (km/h)", function()
        assert.are.equal("kmh", collapse(TN:normalize("km/h")))
    end)

    it("é idempotente", function()
        local once = TN:normalize("Trator João's 200cv, R$150.000!")
        local twice = TN:normalize(once)
        assert.are.equal(once, twice)
    end)

    it("colapsa espaços redundantes e remove pontuação", function()
        assert.are.equal("john 6 r", collapse(TN:normalize("   john    6r  ")))
    end)

    it("não quebra com caracteres mágicos de padrão Lua", function()
        assert.has_no.errors(function()
            TN:normalize("%()-.[ ^$")
        end)
    end)

    it("normalizeForIndex mantém a forma colada como token secundário", function()
        local idx = TN:normalize("6r")
        local both = TN:normalizeForIndex("6r")
        assert.are.equal(idx, both.norm)
        assert.are.equal("6r", both.joined)
    end)
end)

describe("Tokenizer", function()
    it("tokeniza por espaço único, preservando spans em bytes", function()
        local toks = Tokenizer.tokenize("john 6 r")
        assert.are.equal(3, #toks)
        assert.are.equal("john", toks[1].text)
        assert.are.equal(1, toks[1].s)
        assert.are.equal(4, toks[1].e)
        assert.are.equal("6", toks[2].text)
        assert.are.equal("r", toks[3].text)
    end)

    it("nunca produz token vazio", function()
        local toks = Tokenizer.tokenize("  a  b  ")
        for _, t in ipairs(toks) do
            assert.is_true(#t.text > 0)
        end
    end)

    it("string vazia produz zero tokens", function()
        assert.are.equal(0, #Tokenizer.tokenize(""))
    end)
end)
