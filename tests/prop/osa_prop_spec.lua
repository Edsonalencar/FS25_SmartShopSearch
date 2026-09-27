require("tests.support.load").load()
local NS = SmartShopSearch
local Osa = NS.core.Osa

local SEED = 20260927
local N = 500
local ALPHABET = "abcdefghijklmnopqrstuvwxyz"
local MAX_LEN = 12

local function makeRng(seed)
    local state = seed
    return function(mod)
        state = (state * 1103515245 + 12345) % 2147483648
        return state % mod
    end
end

local function randomWord(rng)
    local len = 1 + rng(MAX_LEN)
    local chars = {}
    for i = 1, len do
        chars[i] = ALPHABET:sub(rng(#ALPHABET) + 1, rng(#ALPHABET) + 1)
    end
    return table.concat(chars)
end

--- Levenshtein de referência (sem transposição), lento — só para o teste,
--- nunca no núcleo (OSA é sempre <= Levenshtein clássica, ADR-05).
local function levenshtein(a, b)
    local la, lb = #a, #b
    local prev = {}
    for j = 0, lb do
        prev[j] = j
    end
    for i = 1, la do
        local cur = { [0] = i }
        for j = 1, lb do
            local cost = (a:byte(i) == b:byte(j)) and 0 or 1
            cur[j] = math.min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + cost)
        end
        prev = cur
    end
    return prev[lb]
end

describe("Osa.distance (propriedades, 500 pares aleatórios, seed fixa)", function()
    local rng = makeRng(SEED)
    local pairsToTest = {}
    for _ = 1, N do
        pairsToTest[#pairsToTest + 1] = { randomWord(rng), randomWord(rng) }
    end

    it("é simétrica: d(a,b) == d(b,a)", function()
        for _, p in ipairs(pairsToTest) do
            local maxDist = math.max(#p[1], #p[2])
            assert.are.equal(Osa.distance(p[1], p[2], maxDist), Osa.distance(p[2], p[1], maxDist))
        end
    end)

    it("é <= distância de Levenshtein clássica (sem limite de max)", function()
        for _, p in ipairs(pairsToTest) do
            local maxDist = math.max(#p[1], #p[2])
            local osa = Osa.distance(p[1], p[2], maxDist)
            local lev = levenshtein(p[1], p[2])
            assert.is_true(osa <= lev, string.format("OSA(%q,%q)=%d > Levenshtein=%d", p[1], p[2], osa, lev))
        end
    end)

    it("d(a,a) == 0", function()
        for _, p in ipairs(pairsToTest) do
            assert.are.equal(0, Osa.distance(p[1], p[1], math.max(1, #p[1])))
        end
    end)

    it("respeita a desigualdade de tamanho: d(a,b) >= | |a|-|b| |", function()
        for _, p in ipairs(pairsToTest) do
            local maxDist = math.max(#p[1], #p[2])
            local d = Osa.distance(p[1], p[2], maxDist)
            assert.is_true(d >= math.abs(#p[1] - #p[2]))
        end
    end)
end)
