require("tests.support.load").load()
local runner = require("tests.golden.runner")

local FILES = {
    { path = "tests/golden/queries.pt.xml", lang = "pt" },
    { path = "tests/golden/queries.en.xml", lang = "en" },
}

local function fixturesOf(caseNode)
    local attr = caseNode.attrs.fixtures or "synthetic"
    local out = {}
    for name in attr:gmatch("[^,]+") do
        out[#out + 1] = name
    end
    return out
end

-- Métricas agregadas do corpus (precisão@5, MRR, taxa de vazios), impressas
-- e gravadas em dist/golden-metrics.txt ao fim da execução (F2 §2.6).
local metrics = runner.newMetrics()

describe("golden", function()
    teardown(function()
        io.write("\n" .. runner.formatMetrics(metrics))
        runner.writeMetrics(metrics)
    end)

    for _, file in ipairs(FILES) do
        local ok, cases = pcall(runner.loadCases, file.path)
        if ok then
            describe("golden " .. file.lang .. " (" .. file.path .. ")", function()
                for _, caseNode in ipairs(cases) do
                    local id = caseNode.attrs.id or "?"
                    local queryText = caseNode.attrs.query or ""
                    for _, fixtureProfile in ipairs(fixturesOf(caseNode)) do
                        it(string.format("%s [%s] query=%q", id, fixtureProfile, queryText), function()
                            runner.runCase(caseNode, fixtureProfile, file.lang, nil, metrics)
                        end)
                    end
                end
            end)
        end
    end
end)
