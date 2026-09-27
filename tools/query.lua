#!/usr/bin/env lua
-- Script de desenvolvimento: roda uma consulta contra o catálogo sintético e
-- imprime a Query (AST), o top 10, os scores e os `reasons`.
-- Uso: lua tools/query.lua "trtor jon dere entre 200 e 300 cv por menos de 150 mil"
--      lua tools/query.lua "john 6r" tests/fixtures/catalog/synthetic.xml
--      lua tools/query.lua "over 200 hp" tests/fixtures/catalog/synthetic.xml en
package.path = "./?.lua;" .. package.path

require("tests.support.load").load()
local NS = SmartShopSearch
local FixtureCatalogSource = require("tests.stubs.FixtureCatalogSource")
local FakeClock = require("tests.stubs.FakeClock")
local FileDataLoader = require("tests.stubs.FileDataLoader")

local queryText = arg[1]
local fixturePath = arg[2] or "tests/fixtures/catalog/synthetic.xml"
local primaryLocale = arg[3] or "pt"

if not queryText then
    print('Uso: lua tools/query.lua "<consulta>" [fixture.xml] [locale]')
    os.exit(1)
end

local locales = (primaryLocale == "en") and { "en", "pt" } or { "pt", "en" }
local data = NS.app.LinguisticData.new(FileDataLoader.new("src/data"), locales)
local commonUnits = data:commonUnits()
local normalizer = NS.core.TextNormalizer.new({
    protected = (commonUnits and commonUnits.protected) or {},
    currency = { "r$", "$", "€", "£" },
})
local catalog = FixtureCatalogSource.new(fixturePath)
local builder = NS.core.IndexBuilder.new(normalizer)
local diagnostics = NS.app.Diagnostics.new()
local lifecycle =
    NS.app.IndexLifecycle.new(diagnostics, { catalog = catalog, builder = builder, clock = FakeClock.new() })
local settings = {
    get = function(_, key)
        if key == "search#maxResults" then
            return 300
        end
    end,
}
local svc =
    NS.app.SearchService.new({ indexLifecycle = lifecycle, normalizer = normalizer, settings = settings, data = data })

local results, query = svc:search(queryText)

print("=== Query ===")
print("raw:", query.raw)
io.write("terms:      ")
for _, t in ipairs(query.terms) do
    io.write(string.format("%q ", t.text))
end
print()
io.write("concepts:   ")
for _, c in ipairs(query.concepts) do
    io.write(string.format("%s=%s(%.2f) ", c.kind, c.value, c.confidence))
end
print()
io.write("constraints:")
for _, c in ipairs(query.constraints) do
    io.write(string.format(" %s %s [%s, %s]", c.quantity, c.op, tostring(c.min), tostring(c.max)))
end
print()
if query.context then
    print("context:", query.context.kind, query.context.target)
end
io.write("warnings:   ")
for _, w in ipairs(query.warnings or {}) do
    io.write(w .. "; ")
end
print()

print(string.format("\n=== Top %d (de %d) ===", math.min(10, #results), #results))
for i = 1, math.min(10, #results) do
    local r = results[i]
    local name = r.item.fields.name and r.item.fields.name.raw or ("#" .. tostring(r.item.id))
    print(string.format("%2d. %-40s score=%.3f cov=%.2f", i, name, r.score, r.coverage))
    for _, reason in ipairs(r.reasons) do
        print(
            string.format(
                "      reason: kind=%-10s field=%-10s query=%-10s matched=%-15s detail=%s",
                reason.kind,
                reason.field,
                reason.query,
                reason.matched,
                reason.detail or ""
            )
        )
    end
end
