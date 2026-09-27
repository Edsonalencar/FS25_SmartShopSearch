require("tests.support.load").load()
local NS = SmartShopSearch
local TextNormalizer = NS.core.TextNormalizer
local Tokenizer = NS.core.Tokenizer

local SEED = 20260927
local N = 2000
local MAX_LEN = 24

local function randomString(rng)
    local len = rng() % MAX_LEN
    local bytes = {}
    for i = 1, len do
        bytes[i] = string.char(rng() % 256)
    end
    return table.concat(bytes)
end

-- Gerador congruente linear determinístico (independe de math.randomseed
-- entre implementações de Lua, garantindo reprodutibilidade do teste).
local function makeRng(seed)
    local state = seed
    return function()
        state = (state * 1103515245 + 12345) % 2147483648
        return state
    end
end

describe("TextNormalizer (propriedades, 2000 strings aleatórias, seed fixa)", function()
    local normalizer = TextNormalizer.new({
        protected = { { "km/h", "kmh" }, { "m³", "m3" }, { "r$", " r$ " } },
        currency = { "r$", "$", "€", "£" },
    })

    it("normalize é idempotente e nunca lança erro; tokenizer nunca produz token vazio", function()
        local rng = makeRng(SEED)
        for _ = 1, N do
            local s = randomString(rng)
            local once, twice
            assert.has_no.errors(function()
                once = normalizer:normalize(s)
                twice = normalizer:normalize(once)
            end)
            assert.are.equal(once, twice, string.format("não idempotente para %q", s))

            local tokens = Tokenizer.tokenize(once)
            for _, tok in ipairs(tokens) do
                assert.is_true(#tok.text > 0, "tokenizer produziu token vazio para " .. once)
            end
        end
    end)
end)
