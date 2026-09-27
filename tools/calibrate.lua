#!/usr/bin/env lua
-- Calibração dos pesos de ranking (F9, RF-040): busca em grade sobre
-- minScoreRel e as penalidades, maximizando o número de casos golden que
-- passam (proxy de MRR/precisão@5 — nenhum caso pode piorar). Reaproveita
-- tests/golden/runner.lua. Os valores finais (se diferentes do padrão) vão
-- para docs/adr/0015-ranking-weights.md.
--
-- Uso: lua tools/calibrate.lua
package.path = "./?.lua;" .. package.path

require("tests.support.load").load()
local NS = SmartShopSearch
local runner = require("tests.golden.runner")

local FILES = {
    { path = "tests/golden/queries.pt.xml", lang = "pt" },
    { path = "tests/golden/queries.en.xml", lang = "en" },
}

local function loadAllCases()
    local all = {}
    for _, file in ipairs(FILES) do
        local ok, cases = pcall(runner.loadCases, file.path)
        if ok then
            for _, caseNode in ipairs(cases) do
                all[#all + 1] = { node = caseNode, lang = file.lang }
            end
        end
    end
    return all
end

local function fixturesOf(caseNode)
    local attr = caseNode.attrs.fixtures or "synthetic"
    local out = {}
    for name in attr:gmatch("[^,]+") do
        out[#out + 1] = name
    end
    return out
end

--- Roda todos os casos golden com uma dada tabela de pesos; devolve
--- {passed, total, failures={id,...}}.
local function evaluate(weights)
    local cases = loadAllCases()
    local passed, total, failures = 0, 0, {}
    for _, entry in ipairs(cases) do
        for _, fixtureProfile in ipairs(fixturesOf(entry.node)) do
            total = total + 1
            local ok, err = pcall(runner.runCase, entry.node, fixtureProfile, entry.lang, weights)
            if ok then
                passed = passed + 1
            else
                failures[#failures + 1] = (entry.node.attrs.id or "?") .. ": " .. tostring(err)
            end
        end
    end
    return { passed = passed, total = total, failures = failures }
end

local function deepCopy(t)
    if type(t) ~= "table" then
        return t
    end
    local out = {}
    for k, v in pairs(t) do
        out[k] = deepCopy(v)
    end
    return out
end

local function main()
    local Weights = NS.core.Weights
    local baseline = evaluate(Weights)
    print(
        string.format(
            "baseline: %d/%d casos golden passam (pesos padrão de core/rank/Weights.lua)",
            baseline.passed,
            baseline.total
        )
    )
    for _, f in ipairs(baseline.failures) do
        print("  FALHA: " .. f)
    end

    if baseline.passed == baseline.total then
        print("\nO corpus golden atual (sintético, " .. baseline.total .. " casos) já passa 100% com os pesos")
        print("padrão. Uma calibração que mude pesos sem novos casos discriminantes só arriscaria")
        print("overfitting neste corpus pequeno. Grade de candidatos testada mesmo assim, abaixo,")
        print("para confirmar que nenhuma variação razoável piora o resultado:")
    end

    -- Grade pequena de candidatos ao redor dos valores padrão (RF-040): cada
    -- candidato é testado; só substitui o baseline se PASSAR MAIS casos, sem
    -- nunca aceitar um candidato que faça o baseline piorar.
    local candidates = {
        { minScoreRel = 0.20 },
        { minScoreRel = 0.30 },
        { penalty = { shortToken = 0.05, secondaryOnly = 0.1, fuzzyFar = 0.15 } },
        { penalty = { shortToken = 0.15, secondaryOnly = 0.15, fuzzyFar = 0.2 } },
        { coverageFloor = 0.4 },
        { coverageFloor = 0.6 },
    }

    local best = { weights = Weights, result = baseline }
    for i, overrides in ipairs(candidates) do
        local candidate = deepCopy(Weights)
        for k, v in pairs(overrides) do
            if type(v) == "table" then
                for k2, v2 in pairs(v) do
                    candidate[k][k2] = v2
                end
            else
                candidate[k] = v
            end
        end
        local result = evaluate(candidate)
        print(string.format(
            "candidato %d (%s): %d/%d",
            i,
            table.concat(
                (function()
                    local parts = {}
                    for k in pairs(overrides) do
                        parts[#parts + 1] = k
                    end
                    return parts
                end)(),
                ","
            ),
            result.passed,
            result.total
        ))
        if result.passed > best.result.passed then
            best = { weights = candidate, result = result, label = "candidato " .. i }
        end
    end

    if best.result.passed > baseline.passed then
        print(
            string.format(
                "\nMELHOR CANDIDATO ENCONTRADO: %s (%d/%d vs baseline %d/%d) — considerar adotar",
                best.label,
                best.result.passed,
                best.result.total,
                baseline.passed,
                baseline.total
            )
        )
    else
        print("\nNenhum candidato superou o baseline. Mantendo os pesos padrão de core/rank/Weights.lua.")
    end
end

main()
