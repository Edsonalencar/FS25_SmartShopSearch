-- Motor de execução dos testes golden (F2 §2.6 do spec): lê
-- tests/golden/queries.<lang>.xml e os fixtures de tests/fixtures/catalog/,
-- roda cada <case> contra o SearchService e avalia as expectativas.
local xml = require("tests.support.xml")
local IdMatcher = SmartShopSearch.core.IdMatcher
local TextNormalizer = SmartShopSearch.core.TextNormalizer
local IndexBuilder = SmartShopSearch.core.IndexBuilder
local FixtureCatalogSource = require("tests.stubs.FixtureCatalogSource")
local MemoryLogger = require("tests.stubs.MemoryLogger")
local FakeClock = require("tests.stubs.FakeClock")
local FileDataLoader = require("tests.stubs.FileDataLoader")

local M = {}

-- Currency symbols isolados por espaço (L8); as sequências protegidas
-- (km/h, m³, r$) vêm de data/common/units.xml, lido abaixo por locale.
local CURRENCY_SYMBOLS = { "r$", "$", "€", "£" }

local serviceCache = {}

--- @param primaryLocale string  "pt" (padrão, idioma do jogo simulado) ou "en"
local function localesFor(primaryLocale)
    if primaryLocale == "en" then
        return { "en", "pt" }
    end
    return { "pt", "en" }
end

--- Constrói (ou reaproveita) um SearchService sobre um perfil de fixture.
--- @param fixtureProfile string  ex. "synthetic", "base"
--- @param primaryLocale string|nil  "pt" (padrão) ou "en" — define a ordem de
--- locales (decimal/milhar do NumberParser vêm do primeiro) e cacheia por par.
function M.serviceFor(fixtureProfile, primaryLocale)
    primaryLocale = primaryLocale or "pt"
    local cacheKey = fixtureProfile .. "|" .. primaryLocale
    if serviceCache[cacheKey] then
        return serviceCache[cacheKey]
    end
    local NS = SmartShopSearch
    local path = "tests/fixtures/catalog/" .. fixtureProfile .. ".xml"
    local loader = FileDataLoader.new("src/data")
    local logger = MemoryLogger.new()
    local data = NS.app.LinguisticData.new(loader, localesFor(primaryLocale), logger)
    local commonUnits = data:commonUnits()
    local normalizer =
        TextNormalizer.new({ protected = (commonUnits and commonUnits.protected) or {}, currency = CURRENCY_SYMBOLS })
    local catalog = FixtureCatalogSource.new(path)
    local builder = IndexBuilder.new(normalizer)
    local diagnostics = NS.app.Diagnostics.new()
    local lifecycle =
        NS.app.IndexLifecycle.new(diagnostics, { catalog = catalog, builder = builder, clock = FakeClock.new() })
    local settings = {
        get = function(_, key)
            if key == "search#maxResults" then
                return 300
            end
            return nil
        end,
    }
    local svc = NS.app.SearchService.new({
        indexLifecycle = lifecycle,
        normalizer = normalizer,
        settings = settings,
        logger = logger,
        data = data,
    })
    local entry = { service = svc, logger = logger, diagnostics = diagnostics, lifecycle = lifecycle }
    serviceCache[cacheKey] = entry
    return entry
end

local function splitAttr(value)
    local out = {}
    if not value then
        return out
    end
    for word in value:gmatch("%S+") do
        out[#out + 1] = word
    end
    return out
end

local function itemMatchesAttrs(item, attrs)
    if attrs.category and not IdMatcher.matches(attrs.category, item.categoryIdInternal or "") then
        return false
    end
    if attrs.brand and not IdMatcher.matches(attrs.brand, item.brandId or "") then
        return false
    end
    if attrs.origin and item.origin ~= attrs.origin then
        return false
    end
    if attrs.species and item.species ~= attrs.species then
        return false
    end
    if attrs.name then
        local nameRaw = item.fields.name and item.fields.name.raw or ""
        if IdMatcher.matches(attrs.name, nameRaw) == false and nameRaw ~= attrs.name then
            return false
        end
    end
    return true
end

local function conceptAttrs(node)
    return {
        category = node.attrs.category,
        brand = node.attrs.brand,
        origin = node.attrs.origin,
        species = node.attrs.species,
        name = node.attrs.name,
    }
end

--- Avalia um único elemento de expectativa contra o resultado da busca.
--- Lança erro (assert) em caso de falha, para o busted reportar a mensagem.
local function evalExpectation(node, ctx)
    local results, query, logger = ctx.results, ctx.query, ctx.logger
    local tag = node.tag

    if tag == "expectTop" then
        local n = tonumber(node.attrs.n) or #results
        local minHits = tonumber(node.attrs.minHits) or n
        local attrs = conceptAttrs(node)
        local hits = 0
        for i = 1, math.min(n, #results) do
            if itemMatchesAttrs(results[i].item, attrs) then
                hits = hits + 1
            end
        end
        assert(
            hits >= minHits,
            string.format("expectTop: esperado >=%d hits em top %d, obteve %d (query=%q)", minHits, n, hits, query.raw)
        )
    elseif tag == "expectAll" then
        local top = tonumber(node.attrs.top) or #results
        local attrs = conceptAttrs(node)
        for i = 1, math.min(top, #results) do
            assert(
                itemMatchesAttrs(results[i].item, attrs),
                string.format(
                    "expectAll: item #%d (%s) não satisfaz atributos (query=%q)",
                    i,
                    results[i].item.fields.name and results[i].item.fields.name.raw or "?",
                    query.raw
                )
            )
        end
        assert(#results >= top, string.format("expectAll: esperado >= %d resultados, obteve %d", top, #results))
    elseif tag == "expectFirst" then
        assert(#results >= 1, "expectFirst: nenhum resultado (query=" .. tostring(query.raw) .. ")")
        local nameRaw = results[1].item.fields.name and results[1].item.fields.name.raw or ""
        assert(
            nameRaw == node.attrs.name,
            string.format("expectFirst: esperado nome=%q, obteve %q (query=%q)", node.attrs.name, nameRaw, query.raw)
        )
    elseif tag == "expectRankBefore" then
        local posA, posB = nil, nil
        for i, r in ipairs(results) do
            local nm = r.item.fields.name and r.item.fields.name.raw
            if nm == node.attrs.a then
                posA = posA or i
            end
            if nm == node.attrs.b then
                posB = posB or i
            end
        end
        assert(posA, "expectRankBefore: item a=" .. tostring(node.attrs.a) .. " não encontrado nos resultados")
        assert(posB, "expectRankBefore: item b=" .. tostring(node.attrs.b) .. " não encontrado nos resultados")
        assert(
            posA < posB,
            string.format(
                "expectRankBefore: esperado %s antes de %s (posições %d, %d)",
                node.attrs.a,
                node.attrs.b,
                posA,
                posB
            )
        )
    elseif tag == "expectEmpty" then
        assert(#results == 0, string.format("expectEmpty: esperado 0 resultados, obteve %d", #results))
    elseif tag == "expectMaxScore" then
        local maxAllowed = tonumber(node.attrs.value)
        local best = results[1] and results[1].score or 0
        assert(best <= maxAllowed, string.format("expectMaxScore: melhor score %.3f > %.3f", best, maxAllowed))
    elseif tag == "expectConstraint" then
        local specName = node.attrs.spec
        local op = node.attrs.op
        local min = tonumber(node.attrs.min)
        local max = tonumber(node.attrs.max)
        local found = nil
        for _, c in ipairs(query.constraints or {}) do
            if c.quantity == specName and c.op == op then
                found = c
                break
            end
        end
        assert(
            found,
            string.format("expectConstraint: constraint %s/%s não encontrada (query=%q)", specName, op, query.raw)
        )
        local TOL = 0.1
        if min then
            assert(
                found.min and math.abs(found.min - min) <= TOL,
                string.format("expectConstraint: min esperado %.2f, obteve %s", min, tostring(found.min))
            )
        end
        if max then
            assert(
                found.max and math.abs(found.max - max) <= TOL,
                string.format("expectConstraint: max esperado %.2f, obteve %s", max, tostring(found.max))
            )
        end
    elseif tag == "expectConcept" then
        local found = false
        for _, c in ipairs(query.concepts or {}) do
            if c.kind == node.attrs.kind and IdMatcher.matches(node.attrs.value, c.value) then
                found = true
                break
            end
        end
        assert(
            found,
            string.format(
                "expectConcept: %s=%s não encontrado (query=%q)",
                node.attrs.kind,
                node.attrs.value,
                query.raw
            )
        )
    elseif tag == "expectTerms" then
        local expectedText = xml.text(node)
        local expected = splitAttr(expectedText)
        local got = {}
        for _, t in ipairs(query.terms or {}) do
            got[#got + 1] = t.text
        end
        assert(
            table.concat(expected, " ") == table.concat(got, " "),
            string.format(
                "expectTerms: esperado [%s], obteve [%s]",
                table.concat(expected, " "),
                table.concat(got, " ")
            )
        )
    elseif tag == "expectReasons" then
        assert(#results >= 1, "expectReasons: nenhum resultado")
        local field, kind = node.attrs.field, node.attrs.kind
        local found = false
        for _, r in ipairs(results[1].reasons or {}) do
            if (not field or r.field == field) and (not kind or r.kind == kind) then
                found = true
                break
            end
        end
        assert(found, string.format("expectReasons: nenhum reason com field=%s kind=%s no top-1", field, kind))
    elseif tag == "expectNoError" then
        assert(not (logger and logger:hasLevel("error")), "expectNoError: logger registrou erro")
    else
        error("tipo de expectativa golden desconhecido: " .. tostring(tag))
    end
end

--- Roda um único <case>; retorna métricas simples do caso (para agregação).
--- @param primaryLocale string|nil  "pt" (padrão) ou "en" (tests/golden/queries.en.xml)
function M.runCase(caseNode, fixtureProfile, primaryLocale)
    local entry = M.serviceFor(fixtureProfile, primaryLocale)
    local query = caseNode.attrs.query
    local ui = nil -- filtros de UI entram na F7 (painel); FilterEngine já aplica constraints
    local results, parsedQuery = entry.service:search(query, ui)
    local ctx = {
        results = results,
        query = parsedQuery or { raw = query, terms = {}, concepts = {}, constraints = {} },
        logger = entry.logger,
    }
    for _, node in ipairs(caseNode.children) do
        evalExpectation(node, ctx)
    end
    return { empty = (#results == 0) }
end

--- Carrega um arquivo queries.<lang>.xml e devolve a lista de <case>.
function M.loadCases(path)
    local root = xml.load(path)
    assert(root, "arquivo golden não encontrado: " .. path)
    return xml.children(root, "case")
end

return M
